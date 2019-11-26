package PVE::API2::Network::SDN::Controllers;

use strict;
use warnings;

use PVE::SafeSyslog;
use PVE::Tools qw(extract_param);
use PVE::Cluster qw(cfs_read_file cfs_write_file);
use PVE::Network::SDN::Zones;
use PVE::Network::SDN::Controllers;
use PVE::Network::SDN::Controllers::Plugin;
use PVE::Network::SDN::Controllers::EvpnPlugin;
use PVE::Network::SDN::Controllers::FaucetPlugin;

use Storable qw(dclone);
use PVE::JSONSchema qw(get_standard_option);
use PVE::RPCEnvironment;

use PVE::RESTHandler;

use base qw(PVE::RESTHandler);

my $sdn_controllers_type_enum = PVE::Network::SDN::Controllers::Plugin->lookup_types();

my $api_sdn_controllers_config = sub {
    my ($cfg, $id) = @_;

    my $scfg = dclone(PVE::Network::SDN::Controllers::sdn_controllers_config($cfg, $id));
    $scfg->{controller} = $id;
    $scfg->{digest} = $cfg->{digest};

    return $scfg;
};

__PACKAGE__->register_method ({
    name => 'index',
    path => '',
    method => 'GET',
    description => "SDN controllers index.",
    permissions => {
	description => "Only list entries where you have 'SDN.Audit' or 'SDN.Allocate' permissions on '/sdn/controllers/<controller>'",
	user => 'all',
    },
    parameters => {
    	additionalProperties => 0,
	properties => {
	    type => {
		description => "Only list sdn controllers of specific type",
		type => 'string',
		enum => $sdn_controllers_type_enum,
		optional => 1,
	    },
	},
    },
    returns => {
	type => 'array',
	items => {
	    type => "object",
	    properties => { controller => { type => 'string'}, 
			    type => { type => 'string'},
			  },
	},
	links => [ { rel => 'child', href => "{controller}" } ],
    },
    code => sub {
	my ($param) = @_;

	my $rpcenv = PVE::RPCEnvironment::get();
	my $authuser = $rpcenv->get_user();


	my $cfg = PVE::Network::SDN::Controllers::config();

	my @sids = PVE::Network::SDN::Controllers::sdn_controllers_ids($cfg);
	my $res = [];
	foreach my $id (@sids) {
	    my $privs = [ 'SDN.Audit', 'SDN.Allocate' ];
	    next if !$rpcenv->check_any($authuser, "/sdn/controllers/$id", $privs, 1);

	    my $scfg = &$api_sdn_controllers_config($cfg, $id);
	    next if $param->{type} && $param->{type} ne $scfg->{type};

	    my $plugin_config = $cfg->{ids}->{$id};
	    my $plugin = PVE::Network::SDN::Controllers::Plugin->lookup($plugin_config->{type});
	    push @$res, $scfg;
	}

	return $res;
    }});

__PACKAGE__->register_method ({
    name => 'read',
    path => '{controller}',
    method => 'GET',
    description => "Read sdn controller configuration.",
    permissions => {
	check => ['perm', '/sdn/controllers/{controller}', ['SDN.Allocate']],
   },

    parameters => {
    	additionalProperties => 0,
	properties => {
	    controller => get_standard_option('pve-sdn-controller-id'),
	},
    },
    returns => { type => 'object' },
    code => sub {
	my ($param) = @_;

	my $cfg = PVE::Network::SDN::Controllers::config();

	return &$api_sdn_controllers_config($cfg, $param->{controller});
    }});

__PACKAGE__->register_method ({
    name => 'create',
    protected => 1,
    path => '',
    method => 'POST',
    description => "Create a new sdn controller object.",
    permissions => {
	check => ['perm', '/sdn/controllers', ['SDN.Allocate']],
    },
    parameters => PVE::Network::SDN::Controllers::Plugin->createSchema(),
    returns => { type => 'null' },
    code => sub {
	my ($param) = @_;

	my $type = extract_param($param, 'type');
	my $id = extract_param($param, 'controller');

	my $plugin = PVE::Network::SDN::Controllers::Plugin->lookup($type);
	my $opts = $plugin->check_config($id, $param, 1, 1);

        PVE::Network::SDN::Controllers::lock_sdn_controllers_config(
	    sub {

		my $cfg = PVE::Network::SDN::Controllers::config();

		my $scfg = undef;
		if ($scfg = PVE::Network::SDN::Controllers::sdn_controllers_config($cfg, $id, 1)) {
		    die "sdn controller object ID '$id' already defined\n";
		}

		$cfg->{ids}->{$id} = $opts;
		$plugin->on_update_hook($id, $cfg);

		PVE::Network::SDN::Controllers::write_config($cfg);

	    }, "create sdn controller object failed");

	return undef;
    }});

__PACKAGE__->register_method ({
    name => 'revert_configuration',
    protected => 1,
    path => '',
    method => 'DELETE',
    description => "Revert sdn controller changes.",
    permissions => {
	check => ['perm', '/sdn/controllers', ['SDN.Allocate']],
    },
    parameters => {
	additionalProperties => 0,
    },
    returns => { type => 'null' },
    code => sub {
	my ($param) = @_;

	die "no sdn controllers changes to revert" if !-e "/etc/pve/sdn/controllers.cfg.new";
	unlink "/etc/pve/sdn/controllers.cfg.new";

	return undef;
    }});

__PACKAGE__->register_method ({
    name => 'update',
    protected => 1,
    path => '{controller}',
    method => 'PUT',
    description => "Update sdn controller object configuration.",
    permissions => {
	check => ['perm', '/sdn/controllers', ['SDN.Allocate']],
    },
    parameters => PVE::Network::SDN::Controllers::Plugin->updateSchema(),
    returns => { type => 'null' },
    code => sub {
	my ($param) = @_;

	my $id = extract_param($param, 'controller');
	my $digest = extract_param($param, 'digest');

        PVE::Network::SDN::Controllers::lock_sdn_controllers_config(
	 sub {

	    my $cfg = PVE::Network::SDN::Controllers::config();

	    PVE::SectionConfig::assert_if_modified($cfg, $digest);

	    my $scfg = PVE::Network::SDN::Controllers::sdn_controllers_config($cfg, $id);

	    my $plugin = PVE::Network::SDN::Controllers::Plugin->lookup($scfg->{type});
	    my $opts = $plugin->check_config($id, $param, 0, 1);

	    foreach my $k (%$opts) {
		$scfg->{$k} = $opts->{$k};
	    }

	    $plugin->on_update_hook($id, $cfg);

	    PVE::Network::SDN::Controllers::write_config($cfg);

	    }, "update sdn controller object failed");

	return undef;
    }});

__PACKAGE__->register_method ({
    name => 'delete',
    protected => 1,
    path => '{controller}',
    method => 'DELETE',
    description => "Delete sdn controller object configuration.",
    permissions => {
	check => ['perm', '/sdn/controllers', ['SDN.Allocate']],
    },
    parameters => {
    	additionalProperties => 0,
	properties => {
	    controller => get_standard_option('pve-sdn-controller-id', {
                completion => \&PVE::Network::SDN::Controllers::complete_sdn_controllers,
            }),
	},
    },
    returns => { type => 'null' },
    code => sub {
	my ($param) = @_;

	my $id = extract_param($param, 'controller');

        PVE::Network::SDN::Controllers::lock_sdn_controllers_config(
	    sub {

		my $cfg = PVE::Network::SDN::Controllers::config();

		my $scfg = PVE::Network::SDN::Controllers::sdn_controllers_config($cfg, $id);

		my $plugin = PVE::Network::SDN::Controllers::Plugin->lookup($scfg->{type});

		my $transport_cfg = PVE::Network::SDN::Zones::config();

		$plugin->on_delete_hook($id, $transport_cfg);

		delete $cfg->{ids}->{$id};
		PVE::Network::SDN::Controllers::write_config($cfg);

	    }, "delete sdn controller object failed");


	return undef;
    }});

1;
