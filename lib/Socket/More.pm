package Socket::More;

use 5.036000;
use strict;
use warnings;
use Carp;

use Socket ":all";
use Exporter "import";
use AutoLoader;

our %EXPORT_TAGS = ( 'all' => [ qw(
	getifaddrs
	sockaddr_passive

) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '0.01';

sub getifaddrs;
sub AUTOLOAD {
    # This AUTOLOAD is used to 'autoload' constants from the constant()
    # XS function.

    my $constname;
    our $AUTOLOAD;
    ($constname = $AUTOLOAD) =~ s/.*:://;
    croak "&Socket::More::constant not defined" if $constname eq 'constant';
    my ($error, $val) = constant($constname);
    if ($error) { croak $error; }
    {
	no strict 'refs';
	# Fixed between 5.005_53 and 5.005_61
#XXX	if ($] >= 5.00561) {
#XXX	    *$AUTOLOAD = sub () { $val };
#XXX	}
#XXX	else {
	    *$AUTOLOAD = sub { $val };
#XXX	}
    }
    goto &$AUTOLOAD;
}

require XSLoader;
XSLoader::load('Socket::More', $VERSION);

#Network interface stuff
#=======================
#Return a socket configured for the address
sub socket_for_addr{
	my($addr, $type, $protocol)=@_;
	my $fam=sockaddr_family($addr);	
	my $socket;
	CORE::socket $socket, $fam, $type, $protocol;
	$socket;
}

sub unpack_sockaddr{
	my ($package,$addr)=@_;
	my $family=sockaddr_family $addr;
	if($family==AF_INET){
		return unpack_sockaddr_in $addr;
	}
	elsif($family==AF_INET6){
		return unpack_sockaddr_in6 $addr;
	}
	else {
		die "upack_sockaddr: unsported family type";
	}


}





sub make_unix_interface {

	{
		name=>"unix",
		addr=>pack_sockaddr_un("/thii")
	}
}


use Data::Combination;

my $_default_sort_order=[qw<interface family port path>];
sub sockaddr_passive{
	my ($spec)=@_;
	my $r={};
	my $sort_order=$spec->{sort}//$_default_sort_order;
	#If no interface provided assume all
	$r->{interface}=$spec->{interface}//".*";

	#If no family provided assume all
	$r->{family}=$spec->{family}//[AF_INET, AF_INET6, AF_UNIX];	
	
	#Configure port and path
	$r->{port}=$spec->{port}//[];
	$r->{path}=$spec->{path}//[];

	#Need to add an undef value to port and path arrays. Port and path are mutially exclusive
	if(ref($r->{port}) eq "ARRAY"){
		unshift $r->{port}->@*, undef;
	}
	else {
		$r->{port}=[undef, $r->{port}];#AF_INET, AF_INET6, AF_UNIX];
	}

	if(ref($r->{path}) eq "ARRAY"){
		unshift $r->{path}->@*, undef;
	}
	else {
		$r->{path}=[undef, $r->{path}];#AF_INET, AF_INET6, AF_UNIX];
	}


	#Generate combinations
	my $result=Data::Combination::combinations $r;
	

	#Retrieve the interfaces from the os
	my @interfaces=(make_unix_interface, Socket::More::getifaddrs);

	#Poor man dereferencing
	my @results=$result->@*;
	#say STDERR Dumper @results;
	
	#Force preselection of matching interfaces
	@interfaces=grep {
		my $interface=$_;
		scalar grep {$interface->{name}=~ $_->{interface}} @results
	} @interfaces;


	#Validate Family and fill out port and path
	my @output;
	for my $interface (@interfaces){
		my $fam= sockaddr_family($interface->{addr});
		#say STDERR "FAMILY OF INTERFACE: $fam";
		for(@results){
			next if $fam != $_->{family};

			#Filter out any families which are not what we asked for straight up

			goto CLONE if ($fam == AF_UNIX) 
				&& ($interface->{name} eq "unix")
				#&& ("unix"=~ $_->{interface})
				&& (defined($_->{path}))
				&& (!defined($_->{port}));


			goto CLONE if
				($fam == AF_INET or $fam ==AF_INET6)
				&& defined($_->{port})
				&& !defined($_->{path})
				&& ($_->{interface} ne "unix");

			next;
	CLONE:
			my %clone=$_->%*;			
			my $clone=\%clone;
			$clone{data}=$spec->{data};

			#A this point we have a valid family  and port/path combo
			#
			my ($err,$res, $service);


			#Port or path needs to be set
			if($fam == AF_INET){
				my (undef,$ip)=unpack_sockaddr_in($interface->{addr});
				$clone->{addr}=pack_sockaddr_in($_->{port},$ip);
				$clone->{address}=inet_ntop($fam, $ip);
				#$interface->{port}=$_->{port};
				$clone->{interface}=$interface->{name};
			}
			elsif($fam ==AF_INET6){
				my(undef, $ip, $scope, $flow_info)=unpack_sockaddr_in6($interface->{addr});
				$clone->{addr}=pack_sockaddr_in6($_->{port},$ip, $scope,$flow_info);
				$clone->{address}=inet_ntop($fam, $ip);
				$clone->{interface}=$interface->{name};
				#$interface->{port}=$_->{port};
			}
			elsif($fam==AF_UNIX){
				my $path=unpack_sockaddr_un($interface->{addr});			
				$clone->{address}=$_->{path};
				$clone->{addr}=pack_sockaddr_un $_->{path};
				$clone->{interface}=$interface->{name};
			}
			else {
				die "Unsupported family type";
				last;
			}
			#$clone->{interface}=$interface->{name};

			push @output, $clone;		
		}
	}



	#Here we do multi column sorting.
	#First, find the max width of each column
	no warnings "uninitialized";
	my @max_lengths;
	for my $index (0..@$sort_order-1){
		for(@output){
			my $len=length $_;
			$max_lengths[$index]=$len if $len>$max_lengths[$index];
		}
	}

	#Combine the values into string 'keys' width a width of that fount previously
	sort {
		my $aa="";
		my $bb="";
		for my $so (0..@$sort_order-1){
			my $field=$sort_order->[$so];
			if($field=~/port|family/){
				$aa.=sprintf "%-$max_lengths[$so]s", $a->{$sort_order->[$so]};
				$bb.=sprintf "%-$max_lengths[$so]s", $b->{$sort_order->[$so]};
			}
			else{
				$aa.=sprintf "%$max_lengths[$so]s", $a->{$sort_order->[$so]};
				$bb.=sprintf "%$max_lengths[$so]s", $b->{$sort_order->[$so]};
			}
		}
		$aa cmp $bb;
	} @output
}
# Preloaded methods go here.

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Socket::More - List interfaces, passive address generator and more

=head1 SYNOPSIS

	use v5.36;
	use Socket::More ":all";

	#List basic interface information on all available interfaces
	my @ifs=getifaddrs;
	say $_->{name} for @ifs;


	#Create passive (listening) sockets for selected interfaces
	my @passive=sockaddr_passive {
		interface=>	["eth0", "unix"],
		port=>		[5566, 7788],
		path=>"path_to_sock"
	};
		
	#All invalid family/interface/port/path  combinations are filtered out
	#leaving only valid passive sockets
	say $_->{address} for @passive;

=head1 DESCRIPTION

Additional useful (hopefully) subroutines for working with sockets and network
interfaces which are not included in the C<Socket> module. Its intended operate with INET, INET6 and UNIX address families

=head1 API

=head2 getifaddrs

	my @interface=getifaddrs;

Quries the OS for the list of interfaces currently active. Returns a list of
hash references prepresenting the network interfaces. The keys of these hashes
include:
	
=over

=item	name

The text name of the interface

=item flags

Flags set on the interface

=item	addr

Packed sockaddr structure suitable for use with C<bind>


=item	metmask

Packed sockaddr structure of the netmask

=item	dstmask

Packed sockaddr structure of the dstmask


=back


=head2 sockaddr_passive




=head1 SEE ALSO

L<Net::Interface> seems broken at the time of writing
L<IO::Interface> works with IPv4 addressing only


=head1 AUTHOR

Ruben Westerberg, E<lt>drclaw@localE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2022 by Ruben Westerberg

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.36.0 or,
at your option, any later version of Perl 5 you may have available.


=cut
