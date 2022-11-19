package Socket::More;

use 5.036000;
use strict;
use warnings;
use Carp;

use Socket ":all";

use List::Util qw<uniq>;
use Exporter "import";

use AutoLoader;

use Test::Deep qw<eq_deeply>;
use Net::IP;#::XS;
use Sort::Key::Multi qw<siikeysort>;

use Scalar::Util qw<looks_like_number>;
use Data::Combination;

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
	if_nametoindex
	if_indextoname
	if_nameindex

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


#main routine to return passive address structures
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
	my $data=delete $spec->{data};

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

	if(@new_address){
		@$address=@new_address;
		@interfaces=@new_interfaces;
		$r->{interface}=[".*"];
	}
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
				#$clone->{group}=Net::IP::XS::ip_iptypev4(Net::IP::XS->new($clone->{address})->binip);
				$clone->{group}=Net::IP->new($clone->{address})->iptype;
			}
			elsif($fam == AF_INET6){
				my(undef, $ip, $scope, $flow_info)=unpack_sockaddr_in6($interface->{addr});
				$clone->{addr}=pack_sockaddr_in6($_->{port},$ip, $scope,$flow_info);
				$clone->{address}=inet_ntop($fam, $ip);
				$clone->{interface}=$interface->{name};
				#$clone->{group}=Net::IP::XS::ip_iptypev6(Net::IP::XS->new($clone->{address})->binip);
				$clone->{group}=Net::IP->new($clone->{address})->iptype;
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
			next unless grep {$clone->{address}=~ /$_/i } @$address;
			
			next  unless grep {$clone->{group}=~ /$_/i } @$group;

			#copy data to clone
			$clone->{data}=$data;
			push @output, $clone;		
		}
	}

	my @list;

	#Ensure items in list are unique
        push @list, $output[0] if @output;
        for(my $i=1; $i<@output; $i++){
                my $out=$output[$i];
                my $found=List::Util::first {eq_deeply $_, $out} @list;
                push @list, $out unless $found;
        }

	
	@output=@list;
	@output=siikeysort {$_->{interface}, $_->{family}, $_->{type}} @output;
}

#Parser for CLI  -l options
sub parse_passive_spec {
	#splits a string by : and tests each set
	my @output;
	my @full=qw<interface type protocol family port path address group data>;
	for my $input(@_){
		my %spec;

		#split fields by comma, each field is a key value pair,
		#An exception is made for address::port

		my @field=split ",", $input;

		#Add information to the spec
		for my $field (@field){
			if($field!~/=/){
				for($field){
					if(/(.*):(.*)$/){
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
							if($spec{address}[0]=~s|^\[|| and
								$spec{address}[0]=~s|\]$||){
								$spec{family}=[AF_INET6];
							}
							else{
								#assume an ipv4 address
								$spec{family}=[AF_INET];
							}
						}

						#$spec{type}=[SOCK_STREAM];

					}
					else {
						#Unix path
						$spec{path}=[$field];
						#$spec{type}=[SOCK_STREAM];
						$spec{family}=[AF_UNIX];
						$spec{interface}=['unix'];
					}
				}
				#goto PUSH;
				next;
			}
			my ($key, $value)=split "=", $field,2;
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
                        ###############################
                        # elsif($key eq "data"){      #
                        #         $spec{$key}=$value; #
                        #         next;               #
                        # }                           #
                        ###############################
                        #######################################
                        # elsif($key eq "protocol"){          #
                        #         #Convert string to integer  #
                        #         #TODO: service name lookup? #
                        # }                                   #
                        #######################################
			else{
				@val=($value);

			}
			
                        defined($spec{$key})
                                ?  (push $spec{$key}->@*, @val)
                                : ($spec{$key}=[@val]);
				#($spec{$key}=[@val]);
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

