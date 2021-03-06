###############################################################################
# Copyright 2005-2014 CENTREON
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
# As a special exception, the copyright holders of this program give CENTREON
# permission to link this program with independent modules to produce an timeelapsedutable,
# regardless of the license terms of these independent modules, and to copy and
# distribute the resulting timeelapsedutable under terms of CENTREON choice, provided that
# CENTREON also meet, for each linked independent module, the terms  and conditions
# of the license of that module. An independent module is a module which is not
# derived from this program. If you modify this program, you may extend this
# exception to your version of the program, but you are not obliged to do so. If you
# do not wish to do so, delete this exception statement from your version.
#
# For more information : contact@centreon.com
# Author : Mathieu Cinquin <mcinquin@centreon.com>
#
####################################################################################

package apps::bluemind::mode::incoming;

use base qw(centreon::plugins::mode);

use strict;
use warnings;
use centreon::plugins::httplib;
use centreon::plugins::statefile;
use JSON;

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;

    $self->{version} = '1.1';
    $options{options}->add_options(arguments =>
        {
            "hostname:s"        => { name => 'hostname' },
            "port:s"            => { name => 'port', default => '8086'},
            "proto:s"           => { name => 'proto', default => 'http' },
            "urlpath:s"         => { name => 'url_path', default => "/db" },
            "database:s"        => { name => 'database' },
            "username:s"        => { name => 'username' },
            "password:s"        => { name => 'password' },
            "warning:s"         => { name => 'warning' },
            "critical:s"        => { name => 'critical' },
            "timeout:s"         => { name => 'timeout', default => '3' },
        });

    $self->{statefile_value} = centreon::plugins::statefile->new(%options);

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);

    if (($self->{perfdata}->threshold_validate(label => 'warning', value => $self->{option_results}->{warning})) == 0) {
        $self->{output}->add_option_msg(short_msg => "Wrong warning threshold '" . $self->{option_results}->{warning} . "'.");
        $self->{output}->option_exit();
    }
    if (($self->{perfdata}->threshold_validate(label => 'critical', value => $self->{option_results}->{critical})) == 0) {
        $self->{output}->add_option_msg(short_msg => "Wrong critical threshold '" . $self->{option_results}->{critical} . "'.");
        $self->{output}->option_exit();
    }
    if (!defined($self->{option_results}->{hostname})) {
        $self->{output}->add_option_msg(short_msg => "Please set the hostname option");
        $self->{output}->option_exit();
    }
    if (!defined($self->{option_results}->{database})) {
        $self->{output}->add_option_msg(short_msg => "Please set the database option");
        $self->{output}->option_exit();
    }
    if ((!defined($self->{option_results}->{username}) || !defined($self->{option_results}->{password}))) {
        $self->{output}->add_option_msg(short_msg => "You need to set --username= and --password= option");
        $self->{output}->option_exit();
    }

    $self->{statefile_value}->check_options(%options);
}

sub run {
    my ($self, %options) = @_;

    $self->{statefile_value}->read(statefile => 'bluemind_' . $self->{option_results}->{hostname}  . '_' . centreon::plugins::httplib::get_port($self) . '_' . $self->{mode});
    my $old_timestamp = $self->{statefile_value}->get(name => 'last_timestamp');

    my $new_datas = {};
    $new_datas->{last_timestamp} = time();
    $self->{statefile_value}->write(data => $new_datas);

    if (!defined($old_timestamp)) {
        $self->{output}->output_add(severity => 'OK',
                                    short_msg => "Buffer creation...");
        $self->{output}->display();
        $self->{output}->exit();
    }

    $self->{option_results}->{url_path} = $self->{option_results}->{url_path}."/".$self->{option_results}->{database}."/series";
    $self->{option_results}->{query} = 'select sum("success") as "success_sum", sum("failure") as "failure_sum" from lmtpd.deliveries where time > '.$old_timestamp.'s and time < now()';

    my $query_form_get = { q => $self->{option_results}->{query}, p => $self->{option_results}->{password}, u => $self->{option_results}->{username} };
    my $jsoncontent = centreon::plugins::httplib::connect($self, query_form_get => $query_form_get);

    my $json = JSON->new;

    my $webcontent;

    eval {
        $webcontent = $json->decode($jsoncontent);
    };

    if ($@) {
        $self->{output}->add_option_msg(short_msg => "Cannot decode json response");
        $self->{output}->option_exit();
    }

    my $hwebcontent;
    for my $ref (@{ $webcontent }) {
        my $name = $ref->{name};
        my @columns = @{ $ref->{columns} };

        for my $points (@{ $ref->{points} }) {
            my %hash;
            @hash{ @columns } = @$points;
            push @{ $hwebcontent->{$name} }, \%hash;
        }
    }

    my $success_incoming_mails = defined($hwebcontent->{qw(lmtpd.deliveries)}->[0]->{success_sum}) ? $hwebcontent->{qw(lmtpd.deliveries)}->[0]->{success_sum} : '0';
    my $failure_incoming_mails = defined($hwebcontent->{qw(lmtpd.deliveries)}->[0]->{failure_sum}) ? $hwebcontent->{qw(lmtpd.deliveries)}->[0]->{failure_sum} : '0';

    # If not present: failure and success incoming mails are 0
    if (!defined($success_incoming_mails)) {
        $success_incoming_mails = 0;
    }

    if (!defined($failure_incoming_mails)) {
        $failure_incoming_mails = 0;
    }

    my $exit = $self->{perfdata}->threshold_check(value => $failure_incoming_mails, threshold => [ { label => 'critical', 'exit_litteral' => 'critical' }, { label => 'warning', exit_litteral => 'warning' } ]);

    $self->{output}->output_add(severity => $exit,
        short_msg => sprintf("Success Incoming Mails: %d - Failure Incoming Mails: %d",$success_incoming_mails,$failure_incoming_mails));
    $self->{output}->perfdata_add(label => 'success',
        value => sprintf("%d", $success_incoming_mails),
        min => 0,
    );
    $self->{output}->perfdata_add(label => 'failure',
          value => sprintf("%d", $failure_incoming_mails),
          warning => $self->{perfdata}->get_perfdata_for_output(label => 'warning'),
          critical => $self->{perfdata}->get_perfdata_for_output(label => 'critical'),
          min => 0,
    );

    $self->{output}->display();
    $self->{output}->exit();

}

1;

__END__

=head1 MODE

Check Bluemind incoming_mails (success and failure)

=over 8

=item B<--hostname>

IP Addr/FQDN of the Bluemind host

=item B<--port>

Port used by InfluxDB API (Default: '8086')

=item B<--proto>

Specify https if needed (Default: 'http')

=item B<--urlpath>

Set path to get influxdb information (Default: '/db')

=item B<--database>

InfluxDB Database name

=item B<--username>

Specify username for API authentification

=item B<--password>

Specify password for API authentification

=item B<--timeout>

Threshold for HTTP timeout (Default: 3)

=item B<--warning>

Warning Threshold for failure incoming mails

=item B<--critical>

Critical Threshold for failure incoming mails

=back

=cut
