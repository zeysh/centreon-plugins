################################################################################
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
# permission to link this program with independent modules to produce an executable, 
# regardless of the license terms of these independent modules, and to copy and 
# distribute the resulting executable under terms of MERETHIS choice, provided that 
# MERETHIS also meet, for each linked independent module, the terms  and conditions 
# of the license of that module. An independent module is a module which is not 
# derived from this program. If you modify this program, you may extend this 
# exception to your version of the program, but you are not obliged to do so. If you
# do not wish to do so, delete this exception statement from your version.
# 
# For more information : contact@centreon.com
# Authors : Quentin Garnier <qgarnier@merethis.com>
#
####################################################################################

package apps::centreon::local::mode::metaservice;

use base qw(centreon::plugins::mode);

use strict;
use warnings;
use centreon::plugins::misc;
use centreon::common::db;
use centreon::common::logger;

use vars qw($centreon_config);

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                { 
                                  "centreon-config:s"   => { name => 'centreon_config', default => '/etc/centreon/centreon-config.pm' },
                                  "meta-id:s"           => { name => 'meta_id', },
                                });
    $self->{metric_selected} = {};
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);

    if (!defined($self->{option_results}->{meta_id}) || $self->{option_results}->{meta_id} =~ /^[0-9]+$/) {
        $self->{output}->add_option_msg(short_msg => "Need to specify meta-id (numeric value) option.");
        $self->{output}->option_exit();
    }
    require $self->{option_results}->{centreon_config};
}

sub execute_query {
    my ($self, $db, $query) = @_;
    
    my ($status, $stmt) = $self->{centreon_db_centreon}->query();
    if ($status == -1) {
        $self->{output}->output_add(severity => 'UNKNOWN',
                                    short_msg => 'SQL Query error: ' . $query);
        $self->{output}->display();
        $self->{output}->exit();
    }
    return $stmt;
}

sub select_by_regexp {
    my ($self, %options) = @_;
    
    my $count = 0;
    my $stmt = $self->execute_query($self->{centreon_db_centstorage},
                                    "SELECT metrics.metric_id, metrics.metric_name, metrics.current_value FROM index_data, metrics WHERE index_data.service_description LIKE " . $self->{centreon_db_centstorage}->quote($options{regexp_str})) . " AND index.id = metrics.index_id");
    while (($row = $stmt->fetchrow_hashref())) {
        if ($options{metric_select} eq $row->{metric_name}) {
            $self->{metric_selected}->{$row->{metric_id}} = $row->{current_value};
            $count++;
        }
    }
    if ($count == 0) {
        $self->{output}->output_add(severity => 'UNKNOWN',
                                    short_msg => 'Cannot find a metric.');
        $self->{output}->display();
        $self->{output}->exit();
    }
}

sub select_by_list {
    my ($self, %options) = @_;
 
    my $count = 0;
    my $metric_ids = {};
    my $stmt = $self->execute_query($self->{centreon_db_centreon}, "SELECT metric_id FROM `meta_service_relation` WHERE meta_id = '". $self->{option_results}->{meta_id} . "' AND activate = '1'");
    while (($row = $stmt->fetchrow_hashref())) {
        $metrics_ids->{$row->{metric_id}} = 1;
        $count++;
    }
    if ($count == 0) {
        $self->{output}->output_add(severity => 'UNKNOWN',
                                    short_msg => 'Cannot find a metric_id in table meta_service_relation.');
        $self->{output}->display();
        $self->{output}->exit();
    }
    
    $count = 0;
    $stmt = $self->execute_query($self->{centreon_db_centstorage}, 
                                 "SELECT metric_id, current_value FROM metrics WHERE metric_id IN (" . join(',' keys %{$metric_ids}) . ")");
    while (($row = $stmt->fetchrow_hashref())) {
        $self->{metric_selected}->{$row->{metric_id}} = $row->{current_value};
        $count++;
    }
    if ($count == 0) {
        $self->{output}->output_add(severity => 'UNKNOWN',
                                    short_msg => 'Cannot find a metric_id in metrics table.');
        $self->{output}->display();
        $self->{output}->exit();
    }
}

sub calculate {
    my ($self, %options) = @_;
    my $result = 0;
    
    if ($options{calculation} eq "MIN") {
        my @values = sort(values %{$self->{metric_selected}});
        if (defined($values[0])) {
            $result = $values[0];
        }
    } elsif ($options{calculation} eq "MAX") {
        my @values = sort(values %{$self->{metric_selected}});
        if (defined($values[0])) {
            $result = $values[scalar(@values) - 1];
        }
    } elsif ($options{calculation} eq "SOM") {
        foreach my $value (values %{$self->{metric_selected}}) {
            $value =~ s/,/./;
            $result += $value;
        }
    } elsif ($options{calculation} eq "AVE") {
        my @values = values %{$self->{metric_selected}};
        foreach my $value (@values) {
            $value =~ s/,/./;
            $result += $value;
        }
        my $total = scalar(@values);
        if ($total == 0) {
            $total = 1;
        }
        $result = $result / $total;
    }
    return $result;
}

sub run {
    my ($self, %options) = @_;

    $self->{logger} = centreon::common::logger->new();
    $self->{logger}->severity('none');
    $self->{centreon_db_centreon} = centreon::common::db->new(db => $centreon_config->{centreon_db},
                                                              host => $centreon_config->{db_host},
                                                              port => $centreon_config->{db_port},
                                                              user => $centreon_config->{db_user},
                                                              password => $centreon_config->{db_passwd},
                                                              force => 0,
                                                              logger => $self->{logger});
    my $status = $self->{centreon_db_centreon}->connect();
    if ($status == -1) {
        $self->{output}->output_add(severity => 'UNKNOWN',
                                    short_msg => 'Cannot connect to Centreon Database.');
        $self->{output}->display();
        $self->{output}->exit();
    }
    $self->{centreon_db_centstorage} = centreon::common::db->new(db => $centreon_config->{centstorage_db},
                                                                 host => $centreon_config->{db_host},
                                                                 port => $centreon_config->{db_port},
                                                                 user => $centreon_config->{db_user},
                                                                 password => $centreon_config->{db_passwd},
                                                                 force => 0,
                                                                 logger => $self->{logger});
    my $status = $self->{centreon_db_centstorage}->connect();
    if ($status == -1) {
        $self->{output}->output_add(severity => 'UNKNOWN',
                                    short_msg => 'Cannot connect to Centstorage Database.');
        $self->{output}->display();
        $self->{output}->exit();
    }
    
    my $stmt = $self->execute_query($self->{centreon_db_centreon}, "SELECT meta_display, calcul_type, regexp_str, warning, critical, metric, meta_select_mode FROM `meta_service` WHERE meta_id = '". $self->{option_results}->{meta_id} . "' LIMIT 1");
    my $row = $stmt->fetchrow_hashref();
    if (!defined($row)) {
        $self->{output}->output_add(severity => 'UNKNOWN',
                                    short_msg => 'Cannot get meta service informations.');
        $self->{output}->display();
        $self->{output}->exit();
    }
    
    # Set threshold
    if (($self->{perfdata}->threshold_validate(label => 'warning', value => $row->{warning})) == 0) {
       $self->{output}->add_option_msg(short_msg => "Wrong warning threshold '" . $row->{warning} . "'.");
       $self->{output}->option_exit();
    }
    if (($self->{perfdata}->threshold_validate(label => 'critical', value => $row->{critical})) == 0) {
       $self->{output}->add_option_msg(short_msg => "Wrong critical threshold '" . $row->{critical} . "'.");
       $self->{output}->option_exit();
    }
    
    if ($row->{meta_select_mode} == 2) {
        $self->select_by_regexp(regexp_str => $row->{regexp_str}, metric_select => $row->{metric});
    } else {
        $self->select_by_list();
    } 

    my $result = $self->calculate(calculation => $row->{calcul_type});
    
    $self->{output}->display();
    $self->{output}->exit();
}

1;

__END__

=head1 MODE

Do Centreon meta-service checks.

=over 8

=item B<--centreon-config>

Centreon Database Config File (Default: '/etc/centreon/centreon-config.pm').

=item B<--meta-id>

Meta-id to check (required).

=back

=cut
