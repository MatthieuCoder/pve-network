package PVE::Network::SDN::FrrPlugin;

use strict;
use warnings;
use PVE::Network::SDN::Plugin;
use PVE::Tools;
use PVE::INotify;
use PVE::JSONSchema qw(get_standard_option);

use base('PVE::Network::SDN::Plugin');

sub type {
    return 'frr';
}

sub properties {
    return {
        'asn' => {
            type => 'integer',
            description => "autonomous system number",
        },
        'peers' => {
            description => "peers address list.",
            type => 'string',  #fixme: format
        },
	'gateway-nodes' => get_standard_option('pve-node-list'),
        'gateway-external-peers' => {
            description => "upstream bgp peers address list.",
            type => 'string',  #fixme: format
        },
    };
}

sub options {

    return {
	'uplink-id' => { optional => 0 },
        'asn' => { optional => 0 },
        'peers' => { optional => 0 },
	'gateway-nodes' => { optional => 1 },
	'gateway-external-peers' => { optional => 1 },
    };
}

# Plugin implementation
sub generate_frr_config {
    my ($class, $plugin_config, $router, $id, $uplinks, $config) = @_;

    my @peers = split(',', $plugin_config->{'peers'}) if $plugin_config->{'peers'};

    my $asn = $plugin_config->{asn};
    my $uplink = $plugin_config->{'uplink-id'};
    my $gatewaynodes = $plugin_config->{'gateway-nodes'};
    my @gatewaypeers = split(',', $plugin_config->{'gateway-external-peers'}) if $plugin_config->{'gateway-external-peers'};

    return if !$asn;

    my $iface = "uplink$uplink";
    my $ifaceip = "";

    if($uplinks->{$uplink}->{name}) {
	$iface = $uplinks->{$uplink}->{name};
        $ifaceip = PVE::Network::SDN::Plugin::get_first_local_ipv4_from_interface($iface);
    }

    my $is_gateway = undef;
    my $local_node = PVE::INotify::nodename();

    foreach my $gatewaynode (PVE::Tools::split_list($gatewaynodes)) {
        $is_gateway = 1 if $gatewaynode eq $local_node;
    }

    my @router_config = ();

    push @router_config, "bgp router-id $ifaceip";
    push @router_config, "no bgp default ipv4-unicast";
    push @router_config, "coalesce-time 1000";

    foreach my $address (@peers) {
	next if $address eq $ifaceip;
	push @router_config, "neighbor $address remote-as $asn";
    }

    if ($is_gateway) {
	foreach my $address (@gatewaypeers) {
	    push @router_config, "neighbor $address remote-as external";
	}
    }
    push(@{$config->{router}->{"bgp $asn"}->{""}}, @router_config);

    @router_config = ();
    foreach my $address (@peers) {
	next if $address eq $ifaceip;
	push @router_config, "neighbor $address activate";
    }
    push @router_config, "advertise-all-vni";
    push(@{$config->{router}->{"bgp $asn"}->{"address-family"}->{"l2vpn evpn"}}, @router_config);

    if ($is_gateway) {

        @router_config = ();
        #import /32 routes of evpn network from vrf1 to default vrf (for packet return)
        #frr 7.1 tag is bugged -> works fine with 7.1 stable branch(20190829-02-g6ba76bbc1)
        #https://github.com/FRRouting/frr/issues/4905
	foreach my $address (@gatewaypeers) {
	    push @router_config, "neighbor $address activate";
	}
        push(@{$config->{router}->{"bgp $asn"}->{"address-family"}->{"ipv4 unicast"}}, @router_config);
        push(@{$config->{router}->{"bgp $asn"}->{"address-family"}->{"ipv6 unicast"}}, @router_config);

    }

    return $config;
}

sub on_delete_hook {
    my ($class, $routerid, $sdn_cfg) = @_;

    # verify that transport is associated to this router
    foreach my $id (keys %{$sdn_cfg->{ids}}) {
        my $sdn = $sdn_cfg->{ids}->{$id};
        die "router $routerid is used by $id"
            if (defined($sdn->{router}) && $sdn->{router} eq $routerid);
    }
}

sub on_update_hook {
    my ($class, $routerid, $sdn_cfg) = @_;

    # verify that asn is not already used by another router
    my $asn = $sdn_cfg->{ids}->{$routerid}->{asn};
    foreach my $id (keys %{$sdn_cfg->{ids}}) {
	next if $id eq $routerid;
        my $sdn = $sdn_cfg->{ids}->{$id};
        die "asn $asn is already used by $id"
            if (defined($sdn->{asn}) && $sdn->{asn} eq $asn);
    }
}

1;


