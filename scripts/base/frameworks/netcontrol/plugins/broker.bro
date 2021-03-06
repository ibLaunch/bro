##! Broker plugin for the netcontrol framework. Sends the raw data structures
##! used in NetControl on to Broker to allow for easy handling, e.g., of
##! command-line scripts.

module NetControl;

@load ../main
@load ../plugin
@load base/frameworks/broker

@ifdef ( Broker::__enable )

export {
	## This record specifies the configuration that is passed to :bro:see:`NetControl::create_broker`.
	type BrokerConfig: record {
		## The broker topic used to send events to
		topic: string &optional;
		## Broker host to connect to
		host: addr &optional;
		## Broker port to connect to
		bport: port &optional;

		## Do we accept rules for the monitor path? Default true
		monitor: bool &default=T;
		## Do we accept rules for the forward path? Default true
		forward: bool &default=T;

		## Predicate that is called on rule insertion or removal.
		##
		## p: Current plugin state
		##
		## r: The rule to be inserted or removed
		##
		## Returns: T if the rule can be handled by the current backend, F otherwhise
		check_pred: function(p: PluginState, r: Rule): bool &optional;
	};

	## Instantiates the broker plugin.
	global create_broker: function(config: BrokerConfig, can_expire: bool) : PluginState;

	redef record PluginState += {
		## OpenFlow controller for NetControl Broker plugin
		broker_config: BrokerConfig &optional;
		## The ID of this broker instance - for the mapping to PluginStates
		broker_id: count &optional;
	};

	global broker_add_rule: event(id: count, r: Rule);
	global broker_remove_rule: event(id: count, r: Rule, reason: string);

	global broker_rule_added: event(id: count, r: Rule, msg: string);
	global broker_rule_removed: event(id: count, r: Rule, msg: string);
	global broker_rule_exists: event(id: count, r: Rule, msg: string);
	global broker_rule_error: event(id: count, r: Rule, msg: string);
	global broker_rule_timeout: event(id: count, r: Rule, i: FlowInfo);
}

global netcontrol_broker_peers: table[port, string] of PluginState;
global netcontrol_broker_topics: set[string] = set();
global netcontrol_broker_id: table[count] of PluginState = table();
global netcontrol_broker_current_id: count = 0;

event NetControl::broker_rule_added(id: count, r: Rule, msg: string)
	{
	if ( id !in netcontrol_broker_id )
		{
		Reporter::error(fmt("NetControl broker plugin with id %d not found, aborting", id));
		return;
		}

	local p = netcontrol_broker_id[id];

	event NetControl::rule_added(r, p, msg);
	}

event NetControl::broker_rule_exists(id: count, r: Rule, msg: string)
	{
	if ( id !in netcontrol_broker_id )
		{
		Reporter::error(fmt("NetControl broker plugin with id %d not found, aborting", id));
		return;
		}

	local p = netcontrol_broker_id[id];

	event NetControl::rule_exists(r, p, msg);
	}

event NetControl::broker_rule_removed(id: count, r: Rule, msg: string)
	{
	if ( id !in netcontrol_broker_id )
		{
		Reporter::error(fmt("NetControl broker plugin with id %d not found, aborting", id));
		return;
		}

	local p = netcontrol_broker_id[id];

	event NetControl::rule_removed(r, p, msg);
	}

event NetControl::broker_rule_error(id: count, r: Rule, msg: string)
	{
	if ( id !in netcontrol_broker_id )
		{
		Reporter::error(fmt("NetControl broker plugin with id %d not found, aborting", id));
		return;
		}

	local p = netcontrol_broker_id[id];

	event NetControl::rule_error(r, p, msg);
	}

event NetControl::broker_rule_timeout(id: count, r: Rule, i: FlowInfo)
	{
	if ( id !in netcontrol_broker_id )
		{
		Reporter::error(fmt("NetControl broker plugin with id %d not found, aborting", id));
		return;
		}

	local p = netcontrol_broker_id[id];

	event NetControl::rule_timeout(r, i, p);
	}

function broker_name(p: PluginState) : string
	{
	return fmt("Broker-%s", p$broker_config$topic);
	}

function broker_check_rule(p: PluginState, r: Rule) : bool
	{
	local c = p$broker_config;

	if ( p$broker_config?$check_pred )
		return p$broker_config$check_pred(p, r);

	if ( r$target == MONITOR && c$monitor )
		return T;

	if ( r$target == FORWARD && c$forward )
		return T;

	return F;
	}

function broker_add_rule_fun(p: PluginState, r: Rule) : bool
	{
	if ( ! broker_check_rule(p, r) )
		return F;

	Broker::send_event(p$broker_config$topic, Broker::event_args(broker_add_rule, p$broker_id, r));
	return T;
	}

function broker_remove_rule_fun(p: PluginState, r: Rule, reason: string) : bool
	{
	if ( ! broker_check_rule(p, r) )
		return F;

	Broker::send_event(p$broker_config$topic, Broker::event_args(broker_remove_rule, p$broker_id, r, reason));
	return T;
	}

function broker_init(p: PluginState)
	{
	Broker::enable();
	Broker::connect(cat(p$broker_config$host), p$broker_config$bport, 1sec);
	Broker::subscribe_to_events(p$broker_config$topic);
	}

event Broker::outgoing_connection_established(peer_address: string, peer_port: port, peer_name: string)
	{
	if ( [peer_port, peer_address] !in netcontrol_broker_peers )
		return;

	local p = netcontrol_broker_peers[peer_port, peer_address];
	plugin_activated(p);
	}

global broker_plugin = Plugin(
	$name=broker_name,
	$can_expire = F,
	$add_rule = broker_add_rule_fun,
	$remove_rule = broker_remove_rule_fun,
	$init = broker_init
	);

global broker_plugin_can_expire = Plugin(
	$name=broker_name,
	$can_expire = T,
	$add_rule = broker_add_rule_fun,
	$remove_rule = broker_remove_rule_fun,
	$init = broker_init
	);

function create_broker(config: BrokerConfig, can_expire: bool) : PluginState
	{
	if ( config$topic in netcontrol_broker_topics )
		Reporter::warning(fmt("Topic %s was added to NetControl broker plugin twice. Possible duplication of commands", config$topic));
	else
		add netcontrol_broker_topics[config$topic];

	local plugin = broker_plugin;
	if ( can_expire )
		plugin = broker_plugin_can_expire;

	local p = PluginState($plugin=plugin, $broker_id=netcontrol_broker_current_id, $broker_config=config);

	if ( [config$bport, cat(config$host)] in netcontrol_broker_peers )
		Reporter::warning(fmt("Peer %s:%s was added to NetControl broker plugin twice.", config$host, config$bport));
	else
		netcontrol_broker_peers[config$bport, cat(config$host)] = p;

	netcontrol_broker_id[netcontrol_broker_current_id] = p;
	++netcontrol_broker_current_id;

	return p;
	}

@endif
