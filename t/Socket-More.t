use strict;
use warnings;

use Test::More;
use Test::Deep;

use Socket::More;
use Socket ":all";


BEGIN { use_ok('Socket::More') };


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

	

done_testing;
