# @TEST-SERIALIZE: brokercomm
# @TEST-REQUIRES: grep -q ENABLE_BROKER:BOOL=true $BUILD/CMakeCache.txt

# @TEST-EXEC: btest-bg-run recv "bro -b ../recv.bro broker_port=$BROKER_PORT >recv.out"
# @TEST-EXEC: btest-bg-run send "bro -b ../send.bro broker_port=$BROKER_PORT >send.out"

# @TEST-EXEC: btest-bg-wait 20
# @TEST-EXEC: btest-diff recv/recv.out
# @TEST-EXEC: btest-diff send/send.out

@TEST-START-FILE recv.bro

const broker_port: port &redef;
redef exit_only_after_terminate = T;
redef Broker::endpoint_name = "listener";

event bro_init()
	{
	Broker::enable();
	Broker::listen(broker_port, "127.0.0.1");
	}

event Broker::incoming_connection_established(peer_name: string)
	{
	print "Broker::incoming_connection_established", peer_name;
	}

event Broker::incoming_connection_broken(peer_name: string)
	{
	print "Broker::incoming_connection_broken", peer_name;
	terminate();
	}

@TEST-END-FILE

@TEST-START-FILE send.bro

const broker_port: port &redef;
redef exit_only_after_terminate = T;
redef Broker::endpoint_name = "connector";

event bro_init()
	{
	Broker::enable();
	Broker::connect("127.0.0.1", broker_port, 1sec);
	}

event Broker::outgoing_connection_established(peer_address: string,
                                            peer_port: port,
                                            peer_name: string)
	{
	print "Broker::outgoing_connection_established",
	      peer_address, peer_port, peer_name;
	terminate();
	}

@TEST-END-FILE
