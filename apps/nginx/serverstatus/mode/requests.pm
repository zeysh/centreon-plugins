###############################################################################
# Copyright 2005-2013 MERETHIS
# Centreon is developped by : Julien Mathis and Romain Le Merlus under
# GPL Licence 2.0.
# 
# This program is free software; you can redistribute it and/or modify it under 
# the terms of the GNU General Public License as published by the Free Software 
# Foundation ; either version 2 of the License.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A 
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License along with 
# this program; if not, see <http://www.gnu.org/licenses>.
# 
# Linking this program statically or dynamically with other modules is making a 
# combined work based on this program. Thus, the terms and conditions of the GNU 
# General Public License cover the whole combination.
# 
# As a special exception, the copyright holders of this program give MERETHIS 
# permission to link this program with independent modules to produce an timeelapsedutable, 
# regardless of the license terms of these independent modules, and to copy and 
# distribute the resulting timeelapsedutable under terms of MERETHIS choice, provided that 
# MERETHIS also meet, for each linked independent module, the terms  and conditions 
# of the license of that module. An independent module is a module which is not 
# derived from this program. If you modify this program, you may extend this 
# exception to your version of the program, but you are not obliged to do so. If you
# do not wish to do so, delete this exception statement from your version.
# 
# For more information : contact@centreon.com
# Author : Simon BOMM <sbomm@merethis.com>
#
# Based on De Bodt Lieven plugin
####################################################################################

package apps::nginx::serverstatus::mode::requests;

use base qw(centreon::plugins::mode);

use strict;
use warnings;
use centreon::plugins::httplib;
use centreon::plugins::statefile;

my $maps = [
    { counter => 'accepts', output => 'Connections accepted per seconds %.2f', match => 'server accepts handled requests.*?(\d+)' },
    { counter => 'handled', output => 'Connections handled per serconds %.2f', match => 'server accepts handled requests.*?\d+\s+(\d+)' }, 
    { counter => 'requests', output => 'Requests per seconds %.2f', match => 'server accepts handled requests.*?\d+\s+\d+\s+(\d+)' },
];

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;

    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
            {
            "hostname:s"        => { name => 'hostname' },
            "port:s"            => { name => 'port', },
            "proto:s"           => { name => 'proto', default => "http" },
            "urlpath:s"         => { name => 'url_path', default => "/nginx_status" },
            "credentials"       => { name => 'credentials' },
            "username:s"        => { name => 'username' },
            "password:s"        => { name => 'password' },
            "proxyurl:s"        => { name => 'proxyurl' },
            "timeout:s"         => { name => 'timeout', default => '3' },
            });
    foreach (@{$maps}) {
        $options{options}->add_options(arguments => {
                                                    'warning-' . $_->{counter} . ':s'    => { name => 'warning_' . $_->{counter} },
                                                    'critical-' . $_->{counter} . ':s'    => { name => 'critical_' . $_->{counter} },
                                                    });
    }
    $self->{statefile_value} = centreon::plugins::statefile->new(%options);
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);

    foreach (@{$maps}) {
        if (($self->{perfdata}->threshold_validate(label => 'warning-' . $_->{counter}, value => $self->{option_results}->{'warning_' . $_->{counter}})) == 0) {
            $self->{output}->add_option_msg(short_msg => "Wrong warning-" . $_->{counter} . " threshold '" . $self->{option_results}->{'warning_' . $_->{counter}} . "'.");
            $self->{output}->option_exit();
        }
        if (($self->{perfdata}->threshold_validate(label => 'critical-' . $_->{counter}, value => $self->{option_results}->{'critical_' . $_->{counter}})) == 0) {
            $self->{output}->add_option_msg(short_msg => "Wrong critical-" . $_->{counter} . " threshold '" . $self->{option_results}->{'critical_' . $_->{counter}} . "'.");
            $self->{output}->option_exit();
        }
    }
    if (!defined($self->{option_results}->{hostname})) {
        $self->{output}->add_option_msg(short_msg => "Please set the hostname option");
        $self->{output}->option_exit();
    }
    if ((defined($self->{option_results}->{credentials})) && (!defined($self->{option_results}->{username}) || !defined($self->{option_results}->{password}))) {
        $self->{output}->add_option_msg(short_msg => "You need to set --username= and --password= options when --credentials is used");
        $self->{output}->option_exit();
    }
    
    $self->{statefile_value}->check_options(%options);
}

sub run {
    my ($self, %options) = @_;

    my $webcontent = centreon::plugins::httplib::connect($self);
    my ($buffer_creation, $exit) = (0, 0);
    my $new_datas = {};
    my $old_datas = {};
    
    $self->{statefile_value}->read(statefile => 'nginx_' . $self->{option_results}->{hostname}  . '_' . centreon::plugins::httplib::get_port($self) . '_' . $self->{mode});
    $old_datas->{timestamp} = $self->{statefile_value}->get(name => 'timestamp');
    $new_datas->{timestamp} = time();
    foreach (@{$maps}) {
        if ($webcontent !~ /$_->{match}/msi) {
            $self->{output}->output_add(severity => 'UNKNOWN',
                                        short_msg => "Cannot find " . $_->{counter} . " information.");
            next;
        }

        $new_datas->{$_->{counter}} = $1;
        my $tmp_value = $self->{statefile_value}->get(name => $_->{counter});
        if (!defined($tmp_value)) {
            $buffer_creation = 1;
            next;
        }
        if ($new_datas->{$_->{counter}} < $tmp_value) {
            $buffer_creation = 1;
            next;
        }
        
        $exit = 1;
        $old_datas->{$_->{counter}} = $tmp_value;
    }
    
    $self->{statefile_value}->write(data => $new_datas);
    if ($buffer_creation == 1) {
        $self->{output}->output_add(severity => 'OK',
                                    short_msg => "Buffer creation...");
        if ($exit == 0) {
            $self->{output}->display();
            $self->{output}->exit();
        }
    }
    
    foreach (@{$maps}) {
        # In buffer creation.
        next if (!defined($old_datas->{$_->{counter}}));
        if ($new_datas->{$_->{counter}} - $old_datas->{$_->{counter}} == 0) {
            $self->{output}->output_add(severity => 'OK',
                                        short_msg => "Counter '" . $_->{counter} . "' not moved. Have to wait.");
            next;
        }
        
        my $delta_time = $new_datas->{timestamp} - $old_datas->{timestamp};
        $delta_time = 1 if ($delta_time <= 0);
        
        my $value = ($new_datas->{$_->{counter}} - $old_datas->{$_->{counter}}) / $delta_time;
        my $exit = $self->{perfdata}->threshold_check(value => $value, threshold => [ { label => 'critical-' . $_->{counter}, 'exit_litteral' => 'critical' }, { label => 'warning-' . $_->{counter}, 'exit_litteral' => 'warning' }]);
 
        $self->{output}->output_add(severity => $exit,
                                    short_msg => sprintf($_->{output}, $value));

        $self->{output}->perfdata_add(label => $_->{counter},
                                      value => sprintf('%.2f', $value),
                                      warning => $self->{perfdata}->get_perfdata_for_output(label => 'warning-' . $_->{counter}),
                                      critical => $self->{perfdata}->get_perfdata_for_output(label => 'critical-' . $_->{counter}),
                                      min => 0);
        
    }

    $self->{output}->display();
    $self->{output}->exit();

}

1;

__END__

=head1 MODE

Check Nginx Request statistics: number of accepted connections per seconds, number of handled connections per seconds, number of requests per seconds.

=over 8

=item B<--hostname>

IP Addr/FQDN of the webserver host

=item B<--port>

Port used by Apache

=item B<--proxyurl>

Proxy URL if any

=item B<--proto>

Specify https if needed

=item B<--urlpath>

Set path to get server-status page in auto mode (Default: '/nginx_status')

=item B<--credentials>

Specify this option if you access server-status page over basic authentification

=item B<--username>

Specify username for basic authentification (Mandatory if --credentials is specidied)

=item B<--password>

Specify password for basic authentification (Mandatory if --credentials is specidied)

=item B<--timeout>

Threshold for HTTP timeout

=item B<--warning-*>

Warning Threshold. Can be: 'accepts', 'handled', 'requests'.

=item B<--critical-*>

Critical Threshold. Can be: 'accepts', 'handled', 'requests'.

=back

=cut
