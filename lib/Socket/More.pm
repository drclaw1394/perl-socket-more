package Socket::More;

use 5.036000;

#pack_sockaddr_in
#unpack_sockaddr_in
#sockaddr_family 
#unpack_sockaddr_un
# ":all";
use Socket::More::Constants;
use Socket::More::IPRanges;

#use AutoLoader;

#use Net::IP::Lite qw<ip2bin>;
use Data::Cmp qw<cmp_data>;
use Data::Combination;



my @af_2_name;
my %name_2_af;
my @sock_2_name;
my %name_2_sock;
my $IPV4_ANY="0.0.0.0";
my $IPV6_ANY="::";

BEGIN{
	#build a list of address family names from socket
	my @names=grep /^AF_/, keys %Socket::More::Constants::;
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


	@names=grep /^SOCK_/, keys %Socket::More::Constants::;

	#filter out the following bit masks on BSD, to prevent a huge array:
	#define	SOCK_CLOEXEC	0x10000000
	#define	SOCK_NONBLOCK	0x20000000
	
	for my $ignore(qw<SOCK_CLOEXEC SOCK_NONBLOCK>){
		@names=grep $_ ne $ignore, @names;
	}
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



use Export::These qw<
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
	has_IPv4_interface
	has_IPv6_interface
  reify_ports
  reify_ports_unshared

  sockaddr_family
  getaddrinfo
  gai_strerror 

  pack_sockaddr_un
  unpack_sockaddr_un

  pack_sockaddr_in
  unpack_sockaddr_in

  unpack_sockaddr_in6
  pack_sockaddr_in6


  getnameinfo
>;

sub _reexport {
  # Rexport symbols from socket
  #my $target=shift;
  Socket::More::Constaants->import;
}

our $VERSION = 'v0.4.4';

#sub pack_sockaddr_un;

require XSLoader;
XSLoader::load('Socket::More', $VERSION);
sub getifaddrs;
sub string_to_family;
sub string_to_sock;
sub getaddrinfo;
sub getnameinfo;

#Socket stuff

#Basic wrapper around CORE::socket.
#If it looks like an number: Use core perl
#Otherwise, extract socket family from assumed sockaddr and then call core


sub sockaddr_family {
  # first byte is unsigned char length of struct, which is unused....?
  # The second byte is the family type
  unpack "C", substr($_[0],1,1);
  #use Error::Show;
  #say STDERR context(undef);
  #Socket::sockaddr_family($_[0]);
}



sub socket {

	require Scalar::Util;
	#qw<looks_like_number>;
	return &CORE::socket if Scalar::Util::looks_like_number $_[1];

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
#
sub unpack_sockaddr_un {
  #0 is sockaddr len (unused
  #1 is family
  #2 is start of data
  unpack "A*", substr($_[0],2);
}
sub pack_sockaddr_un {
  #0 is sockaddr len (unused
  #1 is family
  #2 is start of data
  pack "CCA*", 0, AF_UNIX, $_[0];
}


sub pack_sockaddr_in {
  #0 sockadd len
  #1 family 
  #2 start of data
  #   2-3 port,
  #   4-7 sock_addr
  #   8-15 pad
  #
  pack "CCna4x8", 0, AF_INET, $_[0], $_[1];
}

sub unpack_sockaddr_in {

  my ($port, $addr)=unpack "na4", substr($_[0], 2);
  ($port,$addr);
}


sub pack_sockaddr_in6 {
  #port, $ip, $scope $flow
  pack "CCnNa16N", 0, AF_INET6, $_[0], $_[3]//0, $_[1], $_[2]//0;
}

sub unpack_sockaddr_in6{
  my($port,$flow,$ip,$scope)=unpack "nNa16N", substr($_[0], 2);
  ($port,$ip, $scope, $flow);
}

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
	require Scalar::Util;
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
	
  ######
  #v0.4.0 adds string support for type and family
  
  # Convert to arrays for unified interface 
  for($r->{type}, $r->{family}){
    unless(ref eq "ARRAY"){
      $_=[$_];
    }
  }

  for($r->{type}->@*){
    unless(Scalar::Util::looks_like_number $_){
      ($_)=string_to_sock $_;
    }
  }

  for($r->{family}->@*){
    unless(Scalar::Util::looks_like_number $_){
      ($_)=string_to_family $_;
    }
  }
  # End
  #####


	#NOTE: Need to add an undef value to port and path arrays. Port and path are
	#mutually exclusive
	if(ref($r->{port}) eq "ARRAY"){
		unshift $r->{port}->@*, undef;
	}
	else {
		$r->{port}=[undef, $r->{port}];
	}


	if(ref($r->{path}) eq "ARRAY"){
		unshift $r->{path}->@*, undef;
	}
	else {
		$r->{path}=[undef, $r->{path}];
	}

	die "No port number specified, no address information will be returned" if ($r->{port}->@*==0) or ($r->{path}->@*==0);

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
    #push @new_interfaces, ({name=>$IPV4_ANY,addr=>pack_sockaddr_in 0, inet_pton AF_INET, $IPV4_ANY});
    my @results;
    Socket::More::getaddrinfo(
      $IPV4_ANY,
      "0",
      {flags=>NI_NUMERICHOST|NI_NUMERICSERV, family=>AF_INET},
      \@results
    );

		push @new_interfaces, ({name=>$IPV4_ANY,addr=>$results[0]{addr}});
      #pack_sockaddr_in 0, inet_pton AF_INET, $IPV4_ANY});
	}

	if(grep /$IPV6_ANY/, @$address){
		#$r->{interface}=[$IPV6_ANY];
		push @new_spec_int, $IPV6_ANY;
		#@$address=($IPV6_ANY);
		push @new_address, $IPV6_ANY;
    push @new_fam, AF_INET6;
    #push @new_interfaces, ({name=>$IPV6_ANY, addr=>pack_sockaddr_in6 0, inet_pton AF_INET6, $IPV6_ANY});
    my @results;
    Socket::More::getaddrinfo(
      $IPV6_ANY,
      "0",
      {flags=>NI_NUMERICHOST|NI_NUMERICSERV, family=>AF_INET6},
      \@results
    );
    push @new_interfaces, ({name=>$IPV6_ANY, addr=>$results[0]{addr}});
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
  no warnings "uninitialized";
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

        # Get the hostname/ip address as human readable string aka inet_ntop($fam, $ip);
        getnameinfo($interface->{addr}, my $host="", my $port="", NI_NUMERICHOST|NI_NUMERICSERV);

				$clone->{address}=$host;

        # Pack with desired port
				$clone->{addr}=pack_sockaddr_in($_->{port},$ip);

				#$interface->{port}=$_->{port};
				$clone->{interface}=$interface->{name};
        $clone->{group}=ipv4_group $clone->{address};#ip_iptypev4 ip2bin($clone->{address});
			}
			elsif($fam == AF_INET6){
				my(undef, $ip, $scope, $flow_info)=unpack_sockaddr_in6($interface->{addr});
        getnameinfo($interface->{addr}, my $host="", my $port="", NI_NUMERICHOST|NI_NUMERICSERV);
				$clone->{address}=$host;#inet_ntop($fam, $ip);

				$clone->{addr}=pack_sockaddr_in6($_->{port},$ip, $scope, $flow_info);
				$clone->{interface}=$interface->{name};
        $clone->{group}=ipv6_group $clone->{address};#ip_iptypev6 ip2bin($clone->{address});
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
          my $found=grep {cmp_data($_, $out)} @list; 
          push @list, $out unless $found;
  }

	
        #@output=@list;
  #@output=siikeysort {$_->{interface}, $_->{family}, $_->{type}} @output;
  @output=sort {
    $a->{interface} cmp $b->{interface} || $a->{family} cmp $b->{family}|| $a->{type} cmp $b->{type}
  } @list;
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
						$spec{port}=length($2)?[$2]:[];

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

      # The string to in constant lookup is also done in sockadd_passive in
      # v0.4.0 onwards. The conversion below is to keep compatible with
      # previous version. Also parsing to an actual value is useful outside of
      # use of this module
      # 
			if($key eq "family"){
				#Convert string to integer
				@val=string_to_family($value);
			}
			elsif($key eq "type"){
				#Convert string to integer
				@val=string_to_sock($value);
			}
			else{
				@val=($value);

			}
			
      defined($spec{$key})
              ?  (push $spec{$key}->@*, @val)
              : ($spec{$key}=[@val]);
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

sub has_IPv4_interface {
	my $spec={
		family=>AF_INET,
		type=>SOCK_STREAM,
		port=>0
	};
	my @results=sockaddr_passive $spec;
	
	@results>=1;

}

sub has_IPv6_interface{
	my $spec={
		family=>AF_INET6,
		type=>SOCK_STREAM,
		port=>0
	};
	my @results=sockaddr_passive $spec;
	
	@results>=1;

}

sub _reify_ports {

    my $shared=shift;
    #if any specs contain a 0 for the port number, then perform a bind to get one from the OS.
    #Then close the socket, and hope that no one takes it :)
    
    my $port;
    map {
      if(defined($_->{port}) and $_->{port}==0){
        if($shared and defined $port){
          $_->{port}=$port;
        }
        else{
          #attempt a bind 
          die "Could not create socket to reify port" unless CORE::socket(my $sock, $_->{family}, $_->{type}, 0);
          die "Could not set reuse address flag" unless setsockopt $sock, SOL_SOCKET,SO_REUSEADDR,1;
          die "Could not bind socket to reify port" unless bind($sock, $_->{addr});
          my $name=getsockname $sock;

          #my ($err, $a, $port)=getnameinfo($name, NI_NUMERICHOST);
          #my ($err, $a, $port)=
          my $ok=getnameinfo($name, my $host="", my $port="", NI_NUMERICHOST);

          if($ok){
            $_->{port}=$port;
          }
          close $sock;
        }
      }

      $_;
    }


    sockaddr_passive @_;

}
sub reify_ports {
    _reify_ports 1, @_;
}
sub reify_ports_unshared {
    _reify_ports 0, @_;
}

sub sockaddr_valid {
	#Determin if the sock address is still a valid passive address
}

sub monitor {

}

1;
__END__

