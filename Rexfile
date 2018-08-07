use Rex -feature => ['1.6'];
use Carp;
use IO::Prompt;

use constant PACKAGES => qw( subutai subutai-p2p subutai-ovs subutai-nginx );
use constant SERVICES => qw( subutai-ovs subutai subutai-p2p subutai-dnsmasq ipfs subutai-nginx );
use constant NETSERVS => qw( dnsmasq subutai-ovs subutai-nginx );
use constant UPDATE_CMD => 'apt-get install --only-upgrade %s';

# Always root user
user "root";

# Run and show output on terminal
sub doit {
    my $cmd = shift;
    my @output = run $cmd;

    say join "\n", @output;
}

desc "Check uptime for  host";
task "uptime", sub {
    doit "uptime";
};

desc "Update subutai management";
task "update_management", sub {
    doit "subutai update rh";
    doit "subutai list";
};

desc "Update subutai packages and check for running services";
task "update_subutai", sub {

    doit "apt update";

    for ( PACKAGES ) { 
        my $cmd = sprintf UPDATE_CMD, $_;
        doit $cmd;
    }

    service $_, ensure => 'started' for ( SERVICES );
};

desc "Restart subutai p2p";
task "restart_p2p", sub {
    service 'subutai-p2p', ensure => 'stop';
    service 'subutai-p2p', ensure => 'start';
};

desc "clean cached memory";
task "free_mem", sub {
    doit "free -h";
    doit "sync; echo 3 > /proc/sys/vm/drop_caches";
    doit "free -h";
};

desc "run fix_it_mike for p2p";
task "fix_it_mike", sub {
    pkg 'curl', ensure => 'present';
    doit 'bash -c "$(curl -fsSL https://raw.github.com/crioto/fix-my-p2p/master/fix-it-mike.sh)"';
};

desc "install subutai system bare metal on new peer OS";
task "install_subutai_metal", sub {
    my $device;
    my $i      = 1;
    my @output = run "lsblk -o KNAME,TYPE,SIZE,MODEL";
    my %disks  = map { $i++ => $_ } grep { /\bdisk\b/ } @output;

    # select disk device for host
    do {
        say "$_ : $disks{$_}" for ( sort keys %disks );
        $device = $disks{ prompt( "-num", "Please select device: " ) };
    } until defined($device);

    my ($dev_name) = split /\s+/, $device;
    my $dev_file = "/dev/$dev_name"; # TODO: should take path from blkid

    append_if_no_such_line "/etc/apt/sources.list",
"deb http://httpredir.debian.org/debian stretch main contrib non-free contrib non-free";
    doit "apt update";
    doit "apt list --upgradable";
    doit "apt -y install  spl-dkms && apt install zfsutils-linux";
    doit "modprobe zfs";
    doit "zpool create -f subutai $dev_file";
    doit 'zfs create -o mountpoint="/var/lib/lxc" subutai/fs';
    doit "apt -y install lxc";
    doit "touch /etc/apt/sources.list.d/subutai.list";
    append_if_no_such_line "/etc/apt/sources.list.d/subutai.list",
      "deb http://deb.subutai.io/subutai prod main";
    doit
"apt-key adv --recv-keys --keyserver keyserver.ubuntu.com C6B2AC7FBEB649F1";
    doit "apt update && apt -y install subutai";
    doit 'systemctl stop nginx && systemctl disable nginx && apt-get update && apt-get upgrade && systemctl restart subutai-nginx && systemctl status subutai-nginx';
    doit "subutai import management";
};

desc "Status of all subutai services";
task "subutai_status", sub {
    my @SERVICES = qw (
      subutai-agent.service       subutai.mount               subutai-p2p.service         subutai.service
      subutai-dnsmasq.service     subutai-nginx.service       subutai-rng.service
      subutai-forwarding.service  subutai-ovs.service         subutai-roaming.service
    );

    for my $service ( @SERVICES ) { 
        doit "systemctl status $service";
    }
};

desc "Restart all subutai services";
task "restart_all_subutai", sub { 
    for my $service ( SERVICES ) { 
        doit "systemctl restart $service";
        doit "systemctl status $service";
    }
};

desc "Restart all subutai network services";
task "restart_network_service", sub {
    for my $service ( NETSERVS ) { 
        doit "systemctl restart $service";
        doit "systemctl status $service";
    }
};

desc "Add tunnel for peer";
task "add_tunnel", sub { 
    doit "subutai tunnel add localhost";
};

desc "List all port mapping";
task "list_port_map" , sub { 
    doit "subutai map --list";
};

desc "List top memory usage";
task "memory_usage", sub {
    say "Top 10 process consuming memory";
    doit "ps aux --sort=-%mem | awk 'NR<=10{print \$0}'"
};

desc "Reboot peer";
task "peer_reboot", sub { 
    my $a = prompt "Really want to do it? y/n\n" ;
    $a =~/y/i ? doit "reboot": say "skipping";
};

# vim: ft=perl
