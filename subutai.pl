#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use 5.010;
use Mojo::UserAgent;
use Carp;
use Storable;
use JSON;
use Data::Dumper;
use URI::URL;
use List::Util qw(any);
use IO::Prompt;
use IO::All;
use File::Spec::Functions;
use List::MoreUtils;
use Getopt::Long;
use Pod::Usage;
use Data::Dumper;


use constant BASE_URL       => 'https://bazaar.subutai.io';
use constant PEER_SPECIFIER => qw (own shared favorite public all);
use constant ERROR_TMPL     => <<EOM;
Error making request for %s
Headers: %s 
Message: %s
Code: %s
EOM
use constant TYPES => map { ref $_ } ( {}, [], qr//, \'' );

my $JSON = JSON->new->allow_nonref;
my $ENVS;

my $verbose;

# Some rest endpoints with validation and parameters for call
my $REST = {
    peer => {
        base_path => '/rest/v1/client/peers/{specifier}',
        params    => {
            specifier => sub {
                my $val = shift;

                # should belong to list
                return any { $_ eq $val } PEER_SPECIFIER;
            }
        }
    },

    ssh_key => {
        base_path => '/rest/v1/client/environments/{env-id}/ssh-keys',
        params    => {
            'env-id' => sub {
                my $val = shift;

                # can be anything greater than 0;
                return length($val);
            }
        }
    },

    login => {
        base_path => '/rest/v1/client/login',
    },

    environment => {
        base_path => '/rest/v1/tray/environments',
    }
};

my $COOKIE = catfile( $ENV{HOME}, '.subutai/bazaar_cookie.txt' );

sub init_ua {
    # no cookie: auth on subutai
    unless ( -f $COOKIE ) {
        auth();
    }

    # otherwise: set cookie
    my $ua = Mojo::UserAgent->new();
    $ua->cookie_jar( retrieve($COOKIE) );
    return $ua;
}

sub auth {
    return if -f $COOKIE; # already set cookies: return

    # otherwise: set cookies
    my ($email, $pwd);
    ASK: {
        $email = prompt "Subutai username: ";
        my $a = prompt "is $email right? (y/n)\n";
        goto ASK unless $a =~ m/y/i;
        $pwd = prompt( "Subutai password: ", -e => '*' );
    }

    my $ua = Mojo::UserAgent->new;
    my $url = mount_url('login');
    my $tx = $ua->post( $url => form => { email => $email, password => $pwd } );

    if ( $tx->success ) {
      SAVE: {
            store $ua->cookie_jar, $COOKIE;
        }
    }
    else {
        my $err = $tx->error;

        # abort with error
        croak sprintf( ERROR_TMPL,
            $url, $tx->res->headers, $err->{message}, $err->{code} );
    }
}

sub list_environments {
    my $url  = mount_url('environment');
    my $ua   = init_ua;
    my $json = decode_json( $ua->get($url)->res->body );
    return $json;
}

sub mount_url {
    my $end_point = $REST->{ shift() };
    my %args      = ref $_[0] ? %{ $_[0] } : ();

    my $path   = $end_point->{base_path};
    my $params = $end_point->{params};

    # substitute all params in path for actual values.
    for ( keys %args ) {
        my $k = "{$_}";       # param named in base path
        my $v = $args{$_};    # value to be assumed for param

        # check if value pass validation subroutine
        croak "value $v failed check" unless $params->{$_}($v);

        $path =~ s/\Q$k\E/$v/g;    # change param for its value
    }

    return BASE_URL . $path;       #return
}

sub list_peers {
    my $specifier = shift;
    croak "Need one of: `" . join(' ', PEER_SPECIFIER ) . "'" unless $specifier;

    my $url = mount_url( peer => { specifier => $specifier } );
    my $ua = init_ua;
    return decode_json( $ua->get($url)->res->body );
}

# init all envs.
sub init_env {
    my $ua = init_ua;
    $ENVS = list_environments;
}

# does parsing to remove prefix
sub parse_env {
    my $key = qr/(?<prefix>\w+)_(?<sufix>\w+)/;
    my @envs;

    # Drop prefix of hash
    foreach my $hash ( @$ENVS ) {
        my %env = map { /$key/; $+{sufix} => $hash->{$_} } keys %$hash;
        push @envs, \%env;
    }

    wantarray ? @envs : \@envs;
}

# check for a valid reference
sub check_ref {
    my $ref   = shift; # mandatory
    my $type  = shift; # optional
    
    return any { $_  eq $ref } TYPES unless $type;
    return ref $ref eq $type;
}

# get environment(s) data using its name pattern
sub get_env_by_name {
    my $pattern = shift;
    croak "Want regexp" unless check_ref( $pattern, 'Regexp' );

    my @envs = parse_env;
    @envs = grep { $_->{name} =~ /$pattern/ } @envs;

    wantarray ? @envs : \@envs;
}

# get container(s) data using its name pattern
sub get_container_by_name {
    my $pattern = shift;
    croak "Want regexp" unless check_ref( $pattern, 'Regexp' );

    my @envs = parse_env;
    #say Dumper(\@envs);
    my @containers = map { @{ $_->{containers} } } @envs;
    @containers = grep { $_->{container_name} =~ /$pattern/ } @containers;

    wantarray ? @containers : \@containers;
}

# list all environments
sub get_all_envs {
    return get_env_by_name qr/.*/ ;
}

# list all containers
sub get_all_containers {
    return get_container_by_name qr/.*/ ;
}

# connect info for container
sub connect_with {
    my $cont_name = shift;
    my @conts = get_container_by_name( $cont_name );

    croak "Container named $cont_name Not found" unless @conts;

    my $solve_ip_port = sub { 
        my $cont = shift;

        my $ip   = $cont->{rh_ip};

        # Container port number is taken as this: ``port number is , actually
        # computed within tray. so port = 10000+{last_number_of_ip} . from your
        # example 172.21.101.3, you take 3 and add 10000 to it, so you will get
        # 10003 as your port '' ( by Kadyr)

        my (undef, undef, undef, $last) = split /\./ , $cont->{container_ip};
        my $port = 10000 + $last;
        return ( $ip, $port );
    };


    # possible containers
    my @containers = map { [ $_->{container_name}, &$solve_ip_port( $_ ) ] } @conts;
}

# construct external command
sub show_cmd {
    my $tuple = shift;

    my ($name, $ip, $port) = @$tuple;

    my $ssh_tmpl = 'ssh -p %d root@%s # %s';

    say sprintf $ssh_tmpl, $port, $ip, $name;
    
}

sub show_peers_name {
    my $json = list_peers('own');

    my @names = map { [ $_->{rh_name}, $_->{rh_local_ip} ] }
                map { @{ $_->{resource_hosts} } } @$json;

    foreach my $name ( @names ) {
        say join(' ', @$name );
    }
}

# entry point
sub main {
    my ($help, $man, $peers) = ( 0, 0, 0 );

    GetOptions(
        "verbose" => \$verbose,
        "help|?" => \$help,
        "man" => \$man,
        "list-peers" => \$peers,
    ) or pod2usage(2);

    pod2usage(0) if $help;
    pod2usage(-exitval => 0, -verbose => 2) if $man;

    if ( $peers ) { 
        show_peers_name();
        exit 0
    }

    init_env;
    my $cont_name = shift @ARGV or pod2usage(1);

    foreach my $cont ( connect_with qr/$cont_name/ ) {
        show_cmd $cont;
    }
}

main();

__END__

=head1 container.pl

 subutai.pl - manage subutai peers and containers

=head1 SYNOPSIS

 containerl.pl [options] [ container_name ]

 Options:
    - help | man        display this help
    - verbose           run with debug info
    - list-peers        show all peer names

=head1 Description

 This program is licensed under GPL.
