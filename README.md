# NAME

Socket::More - Per interface passive address generator, information and more

# SYNOPSIS

Bring into your namespace. This overrides `socket` also:

```perl
    use v5.36;
    use Socket::More ":all";
```

Simple list of all interfaces:

```perl
    #List basic interface information on all available interfaces
    my @ifs=getifaddrs;
    say $_->{name} for @ifs;
```

Flexible way to create interface scoped passive (listen) address across
families. Special 'unix' interface for easy of use. All invalid combinations of
family, port  and paths are discarded:

```perl
    #Create passive (listening) sockets for selected interfaces
    my @passive=sockaddr_passive {
            interface=>     ["eth0", "unix"],
            port=>          [5566, 7788],
            path=>"path_to_sock"
    };
            
    #All invalid family/interface/port/path  combinations are filtered out
    #leaving only valid info
    say $_->{address} for @passive;
```

Can use a socket wrapper which takes family OR a packed address directly:

```perl
    #Notice socket can be called here with the addr OR the family
    for(@passive){
            die "Could not create socket $!"
                    unless socket my $socket, $_->{addr}, SOCK_STREAM,0;

            bind $socket,$_->{addr}
    }

    
```

# DESCRIPTION

Subroutines for working passive network addresses and utilty functions for
conversion of socket types and address families to and from strings.  It's
ntended to operate with INET, INET6 and UNIX address families and complement
the `Socket` module.

Some of the routines implemented are `sockaddr_passive`, `getifaddrs`,
`parse_passive_spec`, `family_to_string`, `string_to_family`. Please see the
[API](https://metacpan.org/pod/API) section for  a complete listing.

Instead of listening to all interfaces with a wildcard addresses, this module
makes it easy to generate the data structures to bind on multiple addresses,
socket types, and families on a particular set of interfaces, by name.  In
short it facilitates solutions to questions like: 'listen on interface eth0 using
IPv6 and port numbers 9090 and 9091.'.

This power is also accessable in helper routines to allow programs to parse
command line arguments which can leverage its flexibilty.

No symbols are exported by default. All symbols can be exported with the ":all"
tag or individually by name

# MOTIVATION

I wanted an easy way to listen on a particular interface ONLY.  The normal way
of wild card addresses "0.0.0.0" or the unspecified IPv6 address, will listen
on all interfaces. Any restrictions on connecting sockets will either need to
be implemented in the firewall or in application code accepting and then
closing the connection, which is a waste of resources.

Manually creating the multitude of potential addresses on the same interface
(especially for IPv6) is a pain to maintain.

# POTENTIAL FUTURE WORK

\-A more expanded network interface queries for byte counts, rates.. etc

\-Support for more address family types (i.e link)

# API

## socket

```perl
    socket $socket, $domain_or_addr, $type, $proto


    example:
            die "$!" unless socket my $socket, AF_INET, SOCK_STREAM,0;

            
            die "$!" unless socket my $socket, $sockaddr, SOCK_STREAM,0;
```

A wrapper around `CORE::socket`.  It checks if the `DOMAIN` is a number.  If
so, it simply calls `CORE::socket` with the supplied arguments.

Otherwise it assumes `DOMAIN` is a packed sockaddr structure and extracts the
domain/family field using `sockaddr_family`. This value is then used as the
`DOMAIN` value in a call to `CORE::socket`.

Return values are as per `CORE::socket`. Please refer to ["perldoc -f socket"](#perldoc-f-socket)
for more.

## getifaddrs

```perl
    my @interfaces=getifaddrs;
```

Queries the OS via  `getifaddr` for the list of interfaces currently active.
Returns a list of hash references representing the network interfaces. The keys
of these hashes include:

- name

    The text name of the interface

- flags

    Flags set on the interface

- addr

    Packed sockaddr structure suitable for use with `bind`

- netmask

    Packed sockaddr structure of the netmask

- dstmask

    Packed sockaddr structure of the dstmask

## family\_to\_string

```perl
    my $string=family_to_string($family);
```

Returns a string label representing `$family`. For example, calling with
AF\_INET, will return a string `"AF_INET"`

## string\_to\_family

```perl
    my @family=string_to_family($pattern);
```

Performs a match of all AF\_.\* names against `$pattern`. Returns a list of
integers for the corresponding address family that matched. Returns an empty
list if the patten/string does not match.

## sock\_to\_string

```perl
    my $string=sock_to_string($type);
```

Returns a string label representing `$type`. For example, calling with the
integer constant SOCK\_STREAM, will return a string `"SOCK_STREAM"`

## string\_to\_sock

```perl
    my @type=string_to_family($string);
```

Performs a match of all SOCK\_.\* names against `$pattern`. Returns a list of
integers for the corresponding socket types that matched. Returns an empty list
if the patten/string does not match.

## sockaddr\_passive

```perl
    my @interfaces=sockadd_passive $specification;
```

Returns a list of 'interface' structures (similar to getifaddr above) which
provide meta data and packed address structures suitable for passive use (i.e
bind) and matching the `$specification`.

A specification hash has optional keys which dictate what addresses are
generated and filtered.
	{
		interface=>"en",
		family=>"INET",
		port=>\[1234\]
		...
	}

The only required keys are `port` and/or `path`. These are used in the
address generation and not as a filter. Other keys like `interface` and
`family` for example are used to restrict the number of addresses created.

Finally keys like `address` are a final filter which are directly matched
against the address 

It can include the following keys:

- interface

    ```perl
        examples: 
        interface=>"eth0"
        interface=>"eth\d*";
        interface=>["eth0", "lo"];
        interface=>"unix";
        interface=>["unix", "lo"];
    ```

    A string or array ref of strings which are used as regex to match interface
    names currently available.

- familiy

    ```perl
        examples: family=>AF_INET family=>[AF_INET, AF_INET6, AF_UNIX]
    ```

    A integer or array ref of integers representing the family type an interface
    supports.

- port

    ```perl
        examples: port=>55554 port=>[12345,12346]
    ```

    The ports used in generating a passive address. Only applied to AF\_INET\*
    families. Ignored for others

- path

    ```perl
        examples: path=>"path_to_socket.sock" path=>["path_to_socket1.sock",
        "path_to_socket2.sock"]
    ```

    The path used in generating a passive address. Only applied to AF\_UNIX
    families. Ignored for others

- address

    ```perl
        exmples: 
                address=>"192\.168\.1\.1" 
                address=>"169\.254\."
    ```

    As string used

- data

    ```perl
        examples: data=>$scalar datea=>{ ca=>$ca_path, pkey=>$p_path}
    ```

    A user field which will be included in each item in the output list. 

## parse\_passive\_spec

```perl
    my @spec=parse_passive_spec($string);
```

Parses a consise string intended to be supplied as a command line argument. The
string consists of one or more fields sperated by commas.

The fields are in key value pairs in the form

```
    key=value
```

key can be any key for `sockaddr_passive`, and `value`is interpreted as a
regex. 

For example, the following parse a sockaddr\_passive specification which would
match SOCK\_STREAM sockets, for both AF\_INET and AF\_INET6 families, on all
avilable interfaces.

```
    family=INET,type=STREAM
```

In the special case of a single field, if the field DOES NOT contain a '=', it
is interpreted as the plack comptable listen switch argument.

```
    HOST:PORT       :PORT PATH
```

This only will generate IPv4 matching specifications, with SOCK\_STREAM type. Note also that HOST is represents a regex not a literal IP, not does it do  host look up

# SEE ALSO

[Net::Interface](https://metacpan.org/pod/Net%3A%3AInterface) seems broken at the time of writing [IO::Interface](https://metacpan.org/pod/IO%3A%3AInterface) works
with IPv4 addressing only

# AUTHOR

Ruben Westerberg, &lt;drclaw@mac.com&lt;gt>

# COPYRIGHT AND LICENSE

Copyright (C) 2022 by Ruben Westerberg

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl or the MIT license.

# DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE.
