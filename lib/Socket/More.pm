package Socket::More;

use 5.036000;
use strict;
use warnings;
use Carp;

use Socket ":all";
use Test::Deep;
use List::Util qw<uniq>;
use Exporter "import";

use AutoLoader;

our @af_2_name;
our %name_2_af;
our @sock_2_name;
our %name_2_sock;

BEGIN{
	#build a list of address family names from socket
	my @names=grep /^AF_/, keys %Socket::;
	no strict;
	for my $name (@names){
		my $val;
		eval {
			$val=&{$name};
		};
		unless($@){
			$name_2_af{$name}=$val;
			$af_2_name[$val]=$name;
		}
	}


	@names=grep /^SOCK_/, keys %Socket::;
	for my $name (@names){
		my $val;
		eval {
			$val=&{$name};
		};
		unless($@){
			$name_2_sock{$name}=$val;
			$sock_2_name[$val]=$name;
		}
	}
}



our %EXPORT_TAGS = ( 'all' => [ qw(
	getifaddrs
	sockaddr_passive
	socket
	family_to_string
	string_to_family
	sock_to_string
	string_to_sock
	unpack_sockaddr

) ] );

our @EXPORT_OK = ( @{$EXPORT_TAGS{'all'} } );

our @EXPORT = qw(

	
);

our $VERSION = '0.1.0';

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

#Socket stuff

#Basic wrapper around CORE::socket.
#If it looks like an number: Use core perl
#Otherwise, extract socket family from assumed sockaddr and then call core

use Scalar::Util qw<looks_like_number>;
sub socket {
	return &CORE::socket if looks_like_number $_[1];

	if(ref($_[1]) eq "HASH"){
		#assume a 'interface object no need for remaining args
		return CORE::socket $_[0], $_[1]{family}, $_[1]{type}, $_[1]{protocol};
	}
	else {
		#Assume a packed string
		my $domain=sockaddr_family($_[1]);
		return CORE::socket $_[0], $domain, $_[2], $_[3];
	}
}

#Network interface stuff
#=======================
#Return a socket configured for the address

sub unpack_sockaddr{
	my ($addr)=@_;
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




#Used as pseudo interface for filtering to work
sub make_unix_interface {

	{
		name=>"unix",
		addr=>pack_sockaddr_un("/thii")
	}
}


use Data::Combination;

#my $_default_sort_order=[qw<interface family port path>];
sub sockaddr_passive{
	my ($spec)=@_;
	my $r={};
	#my $sort_order=$spec->{sort}//$_default_sort_order;
	#If no interface provided assume all
	$r->{interface}=$spec->{interface}//".*";
	$r->{type}=$spec->{type}//[SOCK_STREAM, SOCK_DGRAM];
	$r->{protocol}=$spec->{protocol}//0;

	#If no family provided assume all
	$r->{family}=$spec->{family}//[AF_INET, AF_INET6, AF_UNIX];	
	
	#Configure port and path
	$r->{port}=$spec->{port}//[];
	$r->{path}=$spec->{path}//[];

	#Need to add an undef value to port and path arrays. Port and path are
	#mutually exclusive
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
		scalar grep {$interface->{name} =~ $_->{interface}} @results
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

	my @list;

	push @list, $output[0] if @output;
	for(my $i=1;$i<@output;$i++){
		my $out=$output[$i];
		my $found=List::Util::first {eq_deeply $_,$out} @list;
		push @list, $out unless $found;
	}

	
	@output=@list;
	use Sort::Key::Multi qw<siikeysort>;
	@output=siikeysort {$_->{interface}, $_->{family}, $_->{type}} @output;
        ##########################################################################################
        # #Here we do multi column sorting.                                                      #
        # #First, find the max width of each column                                              #
        # no warnings "uninitialized";                                                           #
        # my @max_lengths;                                                                       #
        # for my $index (0 .. @$sort_order-1){                                                   #
        #         for(@output){                                                                  #
        #                 my $len=length $_;                                                     #
        #                 $max_lengths[$index]=$len if $len>$max_lengths[$index];                #
        #         }                                                                              #
        # }                                                                                      #
        #                                                                                        #
        #                                                                                        #
        # #Combine the values into string 'keys' width a width of that fount previously          #
        # sort {                                                                                 #
        #         my $aa="";                                                                     #
        #         my $bb="";                                                                     #
        #         for my $so (0..@$sort_order-1){                                                #
        #                 my $field=$sort_order->[$so];                                          #
        #                 if($field=~/port|family/){                                             #
        #                         $aa.=sprintf "%-$max_lengths[$so]s", $a->{$sort_order->[$so]}; #
        #                         $bb.=sprintf "%-$max_lengths[$so]s", $b->{$sort_order->[$so]}; #
        #                 }                                                                      #
        #                 else{                                                                  #
        #                         $aa.=sprintf "%$max_lengths[$so]s", $a->{$sort_order->[$so]};  #
        #                         $bb.=sprintf "%$max_lengths[$so]s", $b->{$sort_order->[$so]};  #
        #                 }                                                                      #
        #         }                                                                              #
        #         $aa cmp $bb;                                                                   #
        # } @output                                                                              #
        ##########################################################################################
}

sub family_to_string { $af_2_name[$_[0]]; }
sub string_to_family { $name_2_af{$_[0]}; }

sub sock_to_string { $sock_2_name[$_[0]]; }
sub string_to_sock { $name_2_sock{$_[0]}; }

1;
__END__

=head1 NAME

Socket::More - Scoped passive address generator, interface info and more

=head1 SYNOPSIS

Bring into your name space. This overrides socket also:

	use v5.36;
	use Socket::More ":all";


Simple list of all interfaces:

	#List basic interface information on all available interfaces
	my @ifs=getifaddrs;
	say $_->{name} for @ifs;


Flexible way to create interface scoped passive (listen) address across
families. Special 'unix' interface for easy of use. All invalid combinations of
family, port  and paths are discarded:

	#Create passive (listening) sockets for selected interfaces
	my @passive=sockaddr_passive {
		interface=>	["eth0", "unix"],
		port=>		[5566, 7788],
		path=>"path_to_sock"
	};
		
	#All invalid family/interface/port/path  combinations are filtered out
	#leaving only valid info
	say $_->{address} for @passive;

Optionally can use a socket wrapper which takes family OR a address directly:

	#Notice socket can be called here with the addr OR the family
	for(@passive){
		die "Could not create socket $!"
			unless socket my $socket, $_->{addr}, SOCK_STREAM,0;

		bind $socket,$_->{addr}
	}

	

=head1 DESCRIPTION

Subroutines for working with sockets and network interfaces supplementing the
C<Socket> module. It's intended operate with INET, INET6 and UNIX address
families. More may be added in the future.

The main subroutine of interest is C<sockaddr_passive> for easily generated
scoped passive addresses. This provides a concise way to achieve problems like:

	'listen on interface eth0 using IPv6 and port numbers 9090 and 9091.'.

C<sockaddr_passive> uses C<getifaddrs>, which is also implemented in
this module.


Mapping routines from address family integers to readable strings  and socket
type to readable string are provided. The reverse mappings are also available.

It also provided wrapper C<socket> subroutine, which will work with either
address families or a packed sockaddr structure. You can save a few lines of
code when creating and binding/connecting sockets by using this wrapper.

No symbols are exported by default. All symbols can be exported with the ":all"
tag or individually by name


=head1 MOTIVATION

I wanted an easy way to listen on a particular interface ONLY.  The normal way
of wild card addresses "0.0.0.0" or the unspecified IPv6 address, will listen
on all interfaces. Any restrictions on connecting sockets will either need to
be implemented in the firewall or in application code accepting and then
closing the connection.

Manually creating the multitude of potential addresses on the same interface
(especially for IPv6) was not really an option. Hence this module was born.



=head1 POTENTIAL FUTURE WORK

-A more expanded network interface queries for byte counts, rates.. etc

-Support for more address family types (i.e link)

=head1 API

=head2 socket

	socket $socket, $domain_or_addr, $type, $proto


	example:
		die "$!" unless socket my $socket, AF_INET, SOCK_STREAM,0;

		
		die "$!" unless socket my $socket, $sockaddr, SOCK_STREAM,0;

A wrapper around C<CORE::socket>.  It checks if the C<DOMAIN> is a number.  If
so, it simply calls C<CORE::socket> with the supplied arguments.

Otherwise it assumes C<DOMAIN> is a packed sockaddr structure and extracts the
domain/family field using C<sockaddr_family>. This value is then used as the
C<DOMAIN> value in a call to C<CORE::socket>.

Return values are as per C<CORE::socket>. Please refer to L<perldoc -f socket>
for more.


=head2 getifaddrs

	my @interfaces=getifaddrs;

Queries the OS via  C<getifaddr> for the list of interfaces currently active.
Returns a list of hash references representing the network interfaces. The keys
of these hashes include:
	
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

=head2 family_to_string

	my $string=family_to_string($family);

Returns a string label representing C<$family>. For example, calling with
AF_INET, will return a string C<"AF_INET">


=head2 string_to_family

	my $family=string_to_family($string);

Returns a address family integer from the string label provided. Foe example,
calling with C<"AF_INET"> will return an integer equal to C<Socket> constant
C<AF_INET>


=head2 sock_to_string

	my $string=sock_to_string($type);

Returns a string label representing C<$type>. For example, calling with the
integer constant SOCK_STREAM, will return a string C<"SOCK_STREAM">

=head2 string_to_sock

	my $type=string_to_family($string);

Returns a socket type integer from the string label provided. Foe example,
calling with C<"SOCK_STREAM"> will return an integer equal to constant
C<SOCK_STREAM>


=head2 sockaddr_passive

	my @interfaces=sockadd_passive $specification;

Returns a list of 'interface' structures (as per getifaddr above) which are
configured for passive use (i.e bind) and matching the C<$specification>.


A specification can include the following keys:
	
=over 

=item interface
		
	examples: interface=>"eth0"	interface=>"eth\d*";
	interface=>["eth0", "lo"]; interface=>"unix" interface=>["unix", "lo",
	AF_INET]

A string or array ref of strings which are used as regex to match interface
names currently available.

=item familiy

	examples: family=>AF_INET family=>[AF_INET, AF_INET6, AF_UNIX]

A integer or array ref of integers representing the family type an interface
supports.


=item port

	examples: port=>55554 port=>[12345,12346]

The ports used in generating a passive address. Only applied to AF_INET*
families. Ignored for others


=item path

	examples: path=>"path_to_socket.sock" path=>["path_to_socket1.sock",
	"path_to_socket2.sock"]

The path used in generating a passive address. Only applied to AF_UNIX
families. Ignored for others

=item sort 

	examples: sort=>["interface", "port"]

An array ref containing how the output list is to be sorted. This is 'multi
column' sort.  Any keys from a specification can be included.


=item data

	examples: data=>$scalar datea=>{ ca=>$ca_path, pkey=>$p_path}

A user field which will be included in each item in the output list. 

=back

=head1 SEE ALSO

L<Net::Interface> seems broken at the time of writing L<IO::Interface> works
with IPv4 addressing only

=head1 AUTHOR

Ruben Westerberg, E<lt>drclaw@localE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2022 by Ruben Westerberg

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl or the MIT license.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE.

=cut
