package Socket::More;

use 5.036000;
use strict;
use warnings;
use Carp;

use Socket ":all";

use List::Util qw<uniq>;
use Exporter "import";

use AutoLoader;

use Test::Deep;
use Net::IP;
use Sort::Key::Multi qw<siikeysort>;

our @af_2_name;
our %name_2_af;
our @sock_2_name;
our %name_2_sock;
my $IPV4_ANY="0.0.0.0";
my $IPV6_ANY="::";

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
	parse_passive_spec
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
	
        ##############################################
        # if(ref($r->{interface}) ne "ARRAY"){       #
        #         $r->{interface}=[$r->{interface}]; #
        # }                                          #
        ##############################################

	$r->{type}=$spec->{type}//[SOCK_STREAM, SOCK_DGRAM];
	$r->{protocol}=$spec->{protocol}//0;

	#If no family provided assume all
	$r->{family}=$spec->{family}//[AF_INET, AF_INET6, AF_UNIX];	
	
	#Configure port and path
	$r->{port}=$spec->{port}//[];
	$r->{path}=$spec->{path}//[];
	


	#NOTE: Need to add an undef value to port and path arrays. Port and path are
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

	carp "No port number specified, no address information will be returned" if ($r->{port}->@*==0) or ($r->{path}->@*==0);

	#Delete from combination specification... no need to make more combos
	my $address=delete $spec->{address};
	my $group=delete $spec->{group};
	$address//=".*";
	$group//=".*";

	#Ensure we have an array for later on
	if(ref($address) ne "ARRAY"){
		$address=[$address];
	}

	if(ref($group) ne "ARRAY"){
		$group=[$group];
	}

	my @interfaces=(make_unix_interface, Socket::More::getifaddrs);

	#Check for special cases here and adjust accordingly
	my @new_address;
	my @new_interfaces;
	my @new_spec_int;
	my @new_fam;

	if(grep /$IPV4_ANY/, @$address){
		#$r->{interface}=[$IPV4_ANY];
		push @new_spec_int, $IPV4_ANY;
		#@$address=($IPV4_ANY);
		push @new_address, $IPV4_ANY;
		push @new_fam, AF_INET;
		push @new_interfaces, ({name=>$IPV4_ANY,addr=>pack_sockaddr_in 0, inet_pton AF_INET, $IPV4_ANY});
	}

	if(grep /$IPV6_ANY/, @$address){
		#$r->{interface}=[$IPV6_ANY];
		push @new_spec_int, $IPV6_ANY;
		#@$address=($IPV6_ANY);
		push @new_address, $IPV6_ANY;
		push @new_fam, AF_INET6;
		push @new_interfaces, ({name=>$IPV6_ANY, addr=>pack_sockaddr_in6 0, inet_pton AF_INET6, $IPV6_ANY});
	}

	@$address=@new_address if @new_address;

	@interfaces=@new_interfaces if @new_interfaces;
	$r->{interface}=[".*"];#[@new_spec_int];
	#$r->{family}=[@new_fam];

	#Handle localhost
	if(grep /localhost/, @$address){
		@$address=('^127.0.0.1$','^::1$');
		$r->{interface}=[".*"];
	}
	#Generate combinations
	my $result=Data::Combination::combinations $r;
	

	#Retrieve the interfaces from the os
	#@interfaces=(make_unix_interface, Socket::More::getifaddrs);


	#Poor man dereferencing
	my @results=$result->@*;
	
	#Force preselection of matching interfaces
	@interfaces=grep {
		my $interface=$_;
		scalar grep {$interface->{name} =~ $_->{interface}} @results
	} @interfaces;


	#Validate Family and fill out port and path
	my @output;
	for my $interface (@interfaces){
		my $fam= sockaddr_family($interface->{addr});
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
				my (undef, $ip)=unpack_sockaddr_in($interface->{addr});
				$clone->{addr}=pack_sockaddr_in($_->{port},$ip);
				$clone->{address}=inet_ntop($fam, $ip);
				#$interface->{port}=$_->{port};
				$clone->{interface}=$interface->{name};
				$clone->{group}=Net::IP::ip_iptypev4(Net::IP->new($clone->{address})->binip);
			}
			elsif($fam == AF_INET6){
				my(undef, $ip, $scope, $flow_info)=unpack_sockaddr_in6($interface->{addr});
				$clone->{addr}=pack_sockaddr_in6($_->{port},$ip, $scope,$flow_info);
				$clone->{address}=inet_ntop($fam, $ip);
				$clone->{interface}=$interface->{name};
				$clone->{group}=Net::IP::ip_iptypev6(Net::IP->new($clone->{address})->binip);
			}
			elsif($fam == AF_UNIX){
				my $suffix=$_->{type}==SOCK_STREAM?"_S":"_D";

				$clone->{addr}=pack_sockaddr_un $_->{path}.$suffix;
				my $path=unpack_sockaddr_un($clone->{addr});			
				$clone->{address}=$path;
				$clone->{path}=$path;
				$clone->{interface}=$interface->{name};
				$clone->{group}="UNIX";
			}
			else {
				die "Unsupported family type";
				last;
			}
			#$clone->{interface}=$interface->{name};

			#Final filtering of address and group
			next unless grep {$clone->{address}=~ $_ } @$address;
			
			next  unless grep {$clone->{group}=~ $_ } @$group;

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

#Old style -l cli flags, limited to ipv4 interfaces thanks to the colon.
#
sub parse_passive_spec {
	#splits a string by : and tests each set
	my @output;
	my @full=qw<interface type protocol family port path address group>;
	for my $input(@_){
		my %spec;

		#split fields by comma, each field is a key value pair,
		#An exception is made for address::port

		my @field=split ",", $input;

		#Add information to the spec
		for my $field (@field){
			if($field!~/=/){
				for($field){
					if(/(.*):(.*)/){
						#TCP and ipv4 only
						$spec{address}=[$1];
						$spec{port}=[$2];

						if($spec{address}[0] =~ /localhost/){
							#do not set family
							#$spec{address}=['^127.0.0.1$','^::1$'];
						}
						elsif($spec{address}[0] eq ""){
							$spec{address}=[$IPV6_ANY, $IPV4_ANY];

							#$spec{family}=[AF_INET, AF_INET6];
						}
						else{
							#assume an ipv4 address
							$spec{family}=[AF_INET];
						}

						$spec{type}=[SOCK_STREAM];

					}
					else {
						#Unix path
						$spec{path}=[$field];
						$spec{type}=[SOCK_STREAM];
						$spec{family}=[AF_UNIX];
						$spec{interface}=['unix'];
					}
				}
				#goto PUSH;
				next;
			}
			my ($key, $value)=split "=", $field;
			$key=~s/ //g;
			$value=~s/ //g;
			my @val;
			#Ensure only 0 or 1 keys match
			die "Ambiguous field name: $key" if 2<=grep /^$key/i, @full;
			($key)=grep /^$key/i, @full;

			if($key eq "family"){
				#Convert string to integer
				@val=string_to_family($value);
			}
			elsif($key eq "type"){
				#Convert string to integer
				@val=string_to_sock($value);
			}
			elsif($key eq "protocol"){
				#Convert string to integer
				#TODO: service name lookup?
			}
			else{
				@val=($value);

			}
			
                        ###########################################
                        # defined($spec{$key})                    #
                        #         ?  (push $spec{$key}->@*, @val) #
                        #         : ($spec{$key}=[@val]);         #
                        ###########################################
			($spec{$key}=[@val]);
		}
		PUSH:
		push @output, \%spec;
	}
	@output;
}


sub family_to_string { $af_2_name[$_[0]]; }

sub string_to_family { 
	my ($string)=@_;
	my @found=grep { /$string/i} sort keys %name_2_af;
	@name_2_af{@found}; 
}

sub sock_to_string { $sock_2_name[$_[0]]; }


sub string_to_sock { 
	my ($string)=@_;
	my @found=grep { /$string/i} sort keys %name_2_sock;
	@name_2_sock{@found};
}

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


=item	netmask

Packed sockaddr structure of the netmask

=item	dstmask

Packed sockaddr structure of the dstmask


=back

=head2 family_to_string

	my $string=family_to_string($family);

Returns a string label representing C<$family>. For example, calling with
AF_INET, will return a string C<"AF_INET">


=head2 string_to_family

	my @family=string_to_family($string);

Performs a match of the stirng againt all AF_.* names. Returns a list of
integers for the corresponding address family. Returns an empty list if the
patten/string does not match.


=head2 sock_to_string

	my $string=sock_to_string($type);

Returns a string label representing C<$type>. For example, calling with the
integer constant SOCK_STREAM, will return a string C<"SOCK_STREAM">

=head2 string_to_sock

	my @type=string_to_family($string);

Performs a match of the stirng againt all SOCK_.* names. Returns a list of
integers for the corresponding address family. Returns an empty list if the
patten/string does not match.



=head2 sockaddr_passive

	my @interfaces=sockadd_passive $specification;

Returns a list of 'interface' structures (similar to getifaddr above) which
provide meta data and packed address structures suitable for passive use (i.e
bind) and matching the C<$specification>.


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

=item address

	exmples: 
		address=>"192\.168\.1\.1" 
		address=>"169\.254\."

As string used

=item data

	examples: data=>$scalar datea=>{ ca=>$ca_path, pkey=>$p_path}

A user field which will be included in each item in the output list. 

=back

=head2 parse_passive_spec

	my @spec=parse_passive_spec($string);

Parses a consise string intended to be supplied as a command line argument. The
string consists of one or more fields sperated by commas.

The fields are in key value pairs in the form

	key=value

key can be any key for C<sockaddr_passive>, and C<value>is interpreted as a
regex. 

For example, the following parse a sockaddr_passive specification which would
match SOCK_STREAM sockets, for both AF_INET and AF_INET6 families, on all
avilable interfaces.

	family=INET,type=STREAM


In the special case of a single field, if the field DOES NOT contain a '=', it
is interpreted as the plack comptable listen switch argument.

	HOST:PORT	:PORT PATH

This only will generate IPv4 matching specifications, with SOCK_STREAM type. Note also that HOST is represents a regex not a literal IP, not does it do  host look up



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
