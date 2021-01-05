package PVE::Network::SDN::Ipams::PhpIpamPlugin;

use strict;
use warnings;
use PVE::INotify;
use PVE::Cluster;
use PVE::Tools;

use base('PVE::Network::SDN::Ipams::Plugin');

sub type {
    return 'phpipam';
}

sub properties {
    return {
	url => {
	    type => 'string',
	},
	token => {
	    type => 'string',
	},
	section => {
	    type => 'integer',
	},
    };
}

sub options {

    return {
        url => { optional => 0},
        token => { optional => 0 },
        section => { optional => 0 },
    };
}

# Plugin implementation

sub add_subnet {
    my ($class, $plugin_config, $subnetid, $subnet, $noerr) = @_;

    my $cidr = $subnet->{cidr};
    my $network = $subnet->{network};
    my $mask = $subnet->{mask};

    my $gateway = $subnet->{gateway};
    my $url = $plugin_config->{url};
    my $token = $plugin_config->{token};
    my $section = $plugin_config->{section};
    my $headers = ['Content-Type' => 'application/json; charset=UTF-8', 'Token' => $token];

    #search subnet
    my $internalid = get_prefix_id($url, $cidr, $headers);

    #create subnet
    if (!$internalid) {
	my $params = { subnet => $network,
		   mask => $mask,
		   sectionId => $section,
		  };

	eval {
		PVE::Network::SDN::api_request("POST", "$url/subnets/", $headers, $params);
	};
	if ($@) {
	    die "error add subnet to ipam: $@" if !$noerr;
	}
    }

}

sub del_subnet {
    my ($class, $plugin_config, $subnetid, $subnet, $noerr) = @_;

    my $cidr = $subnet->{cidr};
    my $url = $plugin_config->{url};
    my $token = $plugin_config->{token};
    my $section = $plugin_config->{section};
    my $headers = ['Content-Type' => 'application/json; charset=UTF-8', 'Token' => $token];

    my $internalid = get_prefix_id($url, $cidr, $headers);
    return if !$internalid;

    return; #fixme: check that prefix is empty exluding gateway, before delete

    eval {
	PVE::Network::SDN::api_request("DELETE", "$url/subnets/$internalid", $headers);
    };
    if ($@) {
	die "error deleting subnet from ipam: $@" if !$noerr;
    }

}

sub add_ip {
    my ($class, $plugin_config, $subnetid, $subnet, $ip, $hostname, $mac, $description, $is_gateway, $noerr) = @_;

    my $cidr = $subnet->{cidr};
    my $url = $plugin_config->{url};
    my $token = $plugin_config->{token};
    my $section = $plugin_config->{section};
    my $headers = ['Content-Type' => 'application/json; charset=UTF-8', 'Token' => $token];

    my $internalid = get_prefix_id($url, $cidr, $headers);

    my $params = { ip => $ip,
		   subnetId => $internalid,
		   is_gateway => $is_gateway,
		   hostname => $hostname,
		   description => $description,
		  };
    $params->{mac} = $mac if $mac;

    eval {
	PVE::Network::SDN::api_request("POST", "$url/addresses/", $headers, $params);
    };

    if ($@) {
	die "error add subnet ip to ipam: ip $ip already exist: $@" if !$noerr;
    }
}

sub update_ip {
    my ($class, $plugin_config, $subnetid, $subnet, $ip, $hostname, $mac, $description, $is_gateway, $noerr) = @_;

    my $cidr = $subnet->{cidr};
    my $url = $plugin_config->{url};
    my $token = $plugin_config->{token};
    my $section = $plugin_config->{section};
    my $headers = ['Content-Type' => 'application/json; charset=UTF-8', 'Token' => $token];

    my $ip_id = get_ip_id($url, $ip, $headers);
    die "can't find ip addresse in ipam" if !$ip_id;

    my $params = { 
		   is_gateway => $is_gateway,
		   hostname => $hostname,
		   description => $description,
		  };
    $params->{mac} = $mac if $mac;

    eval {
	PVE::Network::SDN::api_request("PATCH", "$url/addresses/$ip_id", $headers, $params);
    };

    if ($@) {
	die "ipam: error update subnet ip $ip: $@" if !$noerr;
    }
}

sub add_next_freeip {
    my ($class, $plugin_config, $subnetid, $subnet, $hostname, $mac, $description, $noerr) = @_;

    my $cidr = $subnet->{cidr};  
    my $mask = $subnet->{mask};  
    my $url = $plugin_config->{url};
    my $token = $plugin_config->{token};
    my $section = $plugin_config->{section};
    my $headers = ['Content-Type' => 'application/json; charset=UTF-8', 'Token' => $token];

    my $internalid = get_prefix_id($url, $cidr, $headers);

    my $params = { hostname => $hostname,
		   description => $description,
		  };

    $params->{mac} = $mac if $mac;

    my $ip = undef;
    eval {
	my $result = PVE::Network::SDN::api_request("POST", "$url/addresses/first_free/$internalid/", $headers, $params);
	$ip = $result->{data};
    };

    if ($@) {
        die "can't find free ip in subnet $cidr: $@" if !$noerr;
    }

    return "$ip/$mask" if $ip && $mask;
}

sub del_ip {
    my ($class, $plugin_config, $subnetid, $subnet, $ip, $noerr) = @_;

    return if !$ip;

    my $url = $plugin_config->{url};
    my $token = $plugin_config->{token};
    my $headers = ['Content-Type' => 'application/json; charset=UTF-8', 'Token' => $token];

    my $ip_id = get_ip_id($url, $ip, $headers);
    return if !$ip_id;

    eval {
	PVE::Network::SDN::api_request("DELETE", "$url/addresses/$ip_id", $headers);
    };
    if ($@) {
	die "error delete ip $ip: $@" if !$noerr;
    }
}

sub verify_api {
    my ($class, $plugin_config) = @_;

    my $url = $plugin_config->{url};
    my $token = $plugin_config->{token};
    my $sectionid = $plugin_config->{section};
    my $headers = ['Content-Type' => 'application/json; charset=UTF-8', 'Token' => $token];

    eval {
	PVE::Network::SDN::api_request("GET", "$url/sections/$sectionid", $headers);
    };
    if ($@) {
	die "Can't connect to phpipam api: $@";
    }
}

sub on_update_hook {
    my ($class, $plugin_config) = @_;

    PVE::Network::SDN::Ipams::PhpIpamPlugin::verify_api($class, $plugin_config);
}


#helpers

sub get_prefix_id {
    my ($url, $cidr, $headers) = @_;

    my $result = PVE::Network::SDN::api_request("GET", "$url/subnets/cidr/$cidr", $headers);
    my $data = @{$result->{data}}[0];
    my $internalid = $data->{id};
    return $internalid;
}

sub get_ip_id {
    my ($url, $ip, $headers) = @_;
    my $result = PVE::Network::SDN::api_request("GET", "$url/addresses/search/$ip", $headers);
    my $data = @{$result->{data}}[0];
    my $ip_id = $data->{id};
    return $ip_id;
}

1;


