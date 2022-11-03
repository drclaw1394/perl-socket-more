use strict;
use warnings;

use Test::More;
use Test::Deep;

use Socket qw<:all>;



BEGIN { use_ok('Socket::More') };

use Socket::More ":all";
{
	#Test socket wrapper
	my $sock_addr=pack_sockaddr_in(1234, inet_pton(AF_INET, "127.0.0.1"));
	socket my $normal,AF_INET, SOCK_STREAM, 0;
	ok $normal, "Normal socket created";

	CORE::socket my $core, AF_INET, SOCK_STREAM,0;
	ok $core, "Core socket created";
	socket my $wrapper, $sock_addr, SOCK_STREAM,0;
	ok $wrapper, "Wrapper socket created";
	
	my $interface={family=>AF_INET,type=>SOCK_STREAM, protocol=>0};
	socket(my $hash, $interface);
	
	ok getsockname($normal) eq getsockname($core), "Sockets ok";
	ok getsockname($wrapper) eq getsockname($core), "Sockets ok";
	ok getsockname($hash) eq getsockname($core), "Socket ok";
	
}

{
	#Do we get any interfaces at all?
	my @interfaces=Socket::More::getifaddrs;
	ok @interfaces>=1, "interfaces returned";
}

{
	#No port or no path should give 0 results
	my @results=Socket::More::sockaddr_passive( { });
	ok @results==0, "No port, no result";

	@results=Socket::More::sockaddr_passive( {
			port=>[]
		});
	ok @results==0, "No port, no result";
	
	@results=Socket::More::sockaddr_passive( {
			path=>[]
		});

	ok @results==0, "No path, no result";
}
	
{
	#Test default specifications perform the same as explicit options
	#This gives all interfaces, AF_INET AF_INET6 and AF_UNIX
	my @results=Socket::More::sockaddr_passive( {
			path=>["asdf", "path2"],
			port=>[0,10,12]
		});

	#Should give same results
	my @results_family=Socket::More::sockaddr_passive( {
			family=>[AF_INET, AF_INET6, AF_UNIX],
			path=>["asdf", "path2"],
			port=>[0,10,12]
		});


	#Should give same results
	my @results_family_interface=Socket::More::sockaddr_passive( {
			interface=>".*",
			family=>[AF_INET, AF_INET6, AF_UNIX],
			path=>["asdf", "path2"],
			port=>[0,10,12]
		});

	ok cmp_deeply(\@results, \@results_family),"Family ok";
	ok cmp_deeply(\@results, \@results_family_interface),"Family  and interface ok";

}

{
	#say STDERR "BIND testing";
	#Attempt to bind our listeners
	my $unix_sock_name="test_sock";
	if( -S $unix_sock_name){
		unlink $unix_sock_name;
	}
	my @results=Socket::More::sockaddr_passive( {
			path=>[$unix_sock_name],
			port=>[0,0,0]
	});

	for(@results){
		die "Could not make socket $!" unless socket my $socket, $_->{family}, SOCK_STREAM, 0;
		die "Could not bind $!" unless bind $socket, $_->{addr};

		my $name=getsockname($socket);
		if($_->{family}==AF_UNIX){
			my $path=unpack_sockaddr_un($name);
			ok $path eq $unix_sock_name;
			close $socket;
			if( -S $unix_sock_name){
				unlink $unix_sock_name;
			}
		}
		elsif($_->{family} ==AF_INET or  $_->{family}== AF_INET6){
			#Check whe got a non zero port
			my($err, $ip, $port)=getnameinfo($name, NI_NUMERICHOST|NI_NUMERICSERV);
			ok $port != 0, "Non zero port";
			close $socket;

		}
		else{
			
		}
		
	}
	
}
{
	#say STDERR "Interger to string tests";
	#Test the af 2 name and name 2 af 
	#Each system is different by we assume that AF_INET and AF_INET6 are always available
	
	ok AF_INET==string_to_family("AF_INET"), "Name lookup ok";
	ok AF_INET6==string_to_family("AF_INET6"), "Name lookup ok";

	ok "AF_INET" eq family_to_string(AF_INET), "String convert ok";
	ok "AF_INET6" eq family_to_string(AF_INET6), "String convert ok";
	
	ok SOCK_STREAM==string_to_sock("SOCK_STREAM"), "Name lookup ok";
	ok SOCK_DGRAM==string_to_sock("SOCK_DGRAM"), "Name lookup ok";

	ok "SOCK_STREAM" eq sock_to_string(SOCK_STREAM), "String convert ok";
	ok "SOCK_DGRAM" eq sock_to_string(SOCK_DGRAM), "String convert ok";
}

	

done_testing;
