################################################################################
# Copyright 2005-2014 MERETHIS
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

package storage::emc::DataDomain::mode::hardware;

use base qw(centreon::plugins::mode);

use strict;
use warnings;
use storage::emc::DataDomain::lib::functions;
use storage::emc::DataDomain::mode::components::temperature;
use storage::emc::DataDomain::mode::components::psu;
use storage::emc::DataDomain::mode::components::fan;
use storage::emc::DataDomain::mode::components::disk;
use storage::emc::DataDomain::mode::components::battery;

my $oid_sysDescr = '.1.3.6.1.2.1.1.1'; # 'Data Domain OS 5.4.1.1-411752'
my $oid_powerModuleEntry = '.1.3.6.1.4.1.19746.1.1.1.1.1.1';
my $oid_temperatureSensorEntry = '.1.3.6.1.4.1.19746.1.1.2.1.1.1';
my $oid_fanPropertiesEntry = '.1.3.6.1.4.1.19746.1.1.3.1.1.1';
my $oid_nvramBatteryEntry = '.1.3.6.1.4.1.19746.1.2.3.1.1';

my $thresholds = {
    fan => [
        ['notfound', 'OK'],
        ['ok', 'OK'],
        ['failed', 'CRITICAL'],
    ],
    temperature => [
        ['failed', 'CRITICAL'],
        ['ok', 'OK'],
        ['notfound', 'OK'],
        ['absent', 'OK'],
        ['overheatWarning', 'WARNING'],
        ['overheatCritical', 'CRITICAL'],
    ],
    psu => [
        ['absent', 'OK'],
        ['ok', 'OK'],
        ['failed', 'CRITICAL'],
        ['faulty', 'WARNING'],
        ['acnone', 'WARNING'],
        ['unknown', 'UNKNOWN'],
    ],
    disk => [
        ['ok', 'OK'],
        ['spare', 'OK'],
        ['available', 'OK'],
        ['unknown', 'UNKNOWN'],
        ['absent', 'OK'],
        ['failed', 'CRITICAL'],
    ],
    battery => [
        ['ok', 'OK'],
        ['disabled', 'OK'],
        ['discharged', 'WARNING'],
        ['softdisabled', 'OK'],
        ['UNKNOWN', 'UNKNOWN'],
    ],
};

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                { 
                                  "exclude:s"               => { name => 'exclude' },
                                  "component:s"             => { name => 'component', default => 'all' },
                                  "absent-problem:s"        => { name => 'absent' },
                                  "no-component:s"          => { name => 'no_component' },
                                  "threshold-overload:s@"   => { name => 'threshold_overload' },
                                  "warning:s@"              => { name => 'warning' },
                                  "critical:s@"             => { name => 'critical' },
                                });

    $self->{components} = {};
    $self->{no_components} = undef;
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);

    if (defined($self->{option_results}->{no_component})) {
        if ($self->{option_results}->{no_component} ne '') {
            $self->{no_components} = $self->{option_results}->{no_component};
        } else {
            $self->{no_components} = 'critical';
        }
    }
    
    $self->{overload_th} = {};
    foreach my $val (@{$self->{option_results}->{threshold_overload}}) {
        if ($val !~ /^(.*?),(.*?),(.*)$/) {
            $self->{output}->add_option_msg(short_msg => "Wrong threshold-overload option '" . $val . "'.");
            $self->{output}->option_exit();
        }
        my ($section, $status, $filter) = ($1, $2, $3);
        if ($self->{output}->is_litteral_status(status => $status) == 0) {
            $self->{output}->add_option_msg(short_msg => "Wrong threshold-overload status '" . $val . "'.");
            $self->{output}->option_exit();
        }
        $self->{overload_th}->{$section} = [] if (!defined($self->{overload_th}->{$section}));
        push @{$self->{overload_th}->{$section}}, {filter => $filter, status => $status};
    }
    
    $self->{numeric_threshold} = {};
    foreach my $option (('warning', 'critical')) {
        foreach my $val (@{$self->{option_results}->{$option}}) {
            if ($val !~ /^(.*?),(.*?),(.*)$/) {
                $self->{output}->add_option_msg(short_msg => "Wrong $option option '" . $val . "'.");
                $self->{output}->option_exit();
            }
            my ($section, $regexp, $value) = ($1, $2, $3);
            if ($section !~ /(battery|temperature)/) {
                $self->{output}->add_option_msg(short_msg => "Wrong $option option '" . $val . "' (type must be: battery or temperature).");
                $self->{output}->option_exit();
            }
            my $position = 0;
            if (defined($self->{numeric_threshold}->{$section})) {
                $position = scalar(@{$self->{numeric_threshold}->{$section}});
            }
            if (($self->{perfdata}->threshold_validate(label => $option . '-' . $section . '-' . $position, value => $value)) == 0) {
                $self->{output}->add_option_msg(short_msg => "Wrong $option threshold '" . $value . "'.");
                $self->{output}->option_exit();
            }
            $self->{numeric_threshold}->{$section} = [] if (!defined($self->{numeric_threshold}->{$section}));
            push @{$self->{numeric_threshold}->{$section}}, { label => $option . '-' . $section . '-' . $position, threshold => $option, regexp => $regexp };
        }
    }
}

sub run {
    my ($self, %options) = @_;
    # $options{snmp} = snmp object
    $self->{snmp} = $options{snmp};
    
    $self->{results_leef} = $self->{snmp}->get_leef(oids => [ $oid_sysDescr . '.0' ]);
    if (!($self->{os_version} = storage::emc::DataDomain::lib::functions::get_version(value => $self->{results_leef}->{$oid_sysDescr . '.0'}))) {
        $self->{output}->output_add(severity => 'UNKNOWN',
                                    short_msg => 'Cannot get DataDomain OS version.');
        $self->{output}->display();
        $self->{output}->exit();
    }
    
    my $oid_diskPropState;
    if (centreon::plugins::misc::minimal_version($self->{os_version}, '5.x')) {
        $oid_diskPropState = '.1.3.6.1.4.1.19746.1.6.1.1.1.8';
    } else {
        $oid_diskPropState = '.1.3.6.1.4.1.19746.1.6.1.1.1.7';
    }
    
    $self->{results} = $self->{snmp}->get_multiple_table(oids => [
                                                { oid => $oid_powerModuleEntry },
                                                { oid => $oid_temperatureSensorEntry },
                                                { oid => $oid_fanPropertiesEntry },
                                                { oid => $oid_diskPropState },
                                                { oid => $oid_nvramBatteryEntry },
                                               ]);
    
    
    $self->{output}->output_add(long_msg => 'DataDomain OS version: ' . $self->{os_version} . '.');
    if ($self->{option_results}->{component} eq 'all') {
        storage::emc::DataDomain::mode::components::psu::check($self);
        storage::emc::DataDomain::mode::components::fan::check($self);
        storage::emc::DataDomain::mode::components::disk::check($self);
        storage::emc::DataDomain::mode::components::temperature::check($self);
        storage::emc::DataDomain::mode::components::battery::check($self);
    } elsif ($self->{option_results}->{component} eq 'fan') {
        storage::emc::DataDomain::mode::components::fan::check($self);
    } elsif ($self->{option_results}->{component} eq 'psu') {
        storage::emc::DataDomain::mode::components::psu::check($self);
    } elsif ($self->{option_results}->{component} eq 'disk') {
        storage::emc::DataDomain::mode::components::disk::check($self);
    } elsif ($self->{option_results}->{component} eq 'temperature') {
        storage::emc::DataDomain::mode::components::temperature::check($self);
    } elsif ($self->{option_results}->{component} eq 'battery') {
        storage::emc::DataDomain::mode::components::battery::check($self);
    } else {
        $self->{output}->add_option_msg(short_msg => "Wrong option. Cannot find component '" . $self->{option_results}->{component} . "'.");
        $self->{output}->option_exit();
    }
    
    my $total_components = 0;
    my $display_by_component = '';
    my $display_by_component_append = '';
    foreach my $comp (sort(keys %{$self->{components}})) {
        # Skipping short msg when no components
        next if ($self->{components}->{$comp}->{total} == 0 && $self->{components}->{$comp}->{skip} == 0);
        $total_components += $self->{components}->{$comp}->{total} + $self->{components}->{$comp}->{skip};
        my $count_by_components = $self->{components}->{$comp}->{total} + $self->{components}->{$comp}->{skip}; 
        $display_by_component .= $display_by_component_append . $self->{components}->{$comp}->{total} . '/' . $count_by_components . ' ' . $self->{components}->{$comp}->{name};
        $display_by_component_append = ', ';
    }
    
    $self->{output}->output_add(severity => 'OK',
                                short_msg => sprintf("All %s components are ok [%s].", 
                                                     $total_components,
                                                     $display_by_component)
                                );

    if (defined($self->{option_results}->{no_component}) && $total_components == 0) {
        $self->{output}->output_add(severity => $self->{no_components},
                                    short_msg => 'No components are checked.');
    }

    $self->{output}->display();
    $self->{output}->exit();
}

sub check_exclude {
    my ($self, %options) = @_;

    if (defined($options{instance})) {
        if (defined($self->{option_results}->{exclude}) && $self->{option_results}->{exclude} =~ /(^|\s|,)${options{section}}[^,]*#\Q$options{instance}\E#/) {
            $self->{components}->{$options{section}}->{skip}++;
            $self->{output}->output_add(long_msg => sprintf("Skipping $options{section} section $options{instance} instance."));
            return 1;
        }
    } elsif (defined($self->{option_results}->{exclude}) && $self->{option_results}->{exclude} =~ /(^|\s|,)$options{section}(\s|,|$)/) {
        $self->{output}->output_add(long_msg => sprintf("Skipping $options{section} section."));
        return 1;
    }
    return 0;
}

sub absent_problem {
    my ($self, %options) = @_;
    
    if (defined($self->{option_results}->{absent}) && 
        $self->{option_results}->{absent} =~ /(^|\s|,)($options{section}(\s*,|$)|${options{section}}[^,]*#\Q$options{instance}\E#)/) {
        $self->{output}->output_add(severity => 'CRITICAL',
                                    short_msg => sprintf("Component '%s' instance '%s' is not present", 
                                                         $options{section}, $options{instance}));
    }

    $self->{output}->output_add(long_msg => sprintf("Skipping $options{section} section $options{instance} instance (not present)"));
    $self->{components}->{$options{section}}->{skip}++;
    return 1;
}

sub get_severity_numeric {
    my ($self, %options) = @_;
    my $status = 'OK'; # default
    my $thresholds = { warning => undef, critical => undef };
    
    if (defined($self->{numeric_threshold}->{$options{section}})) {
        my $exits = [];
        foreach (@{$self->{numeric_threshold}->{$options{section}}}) {
            if ($options{instance} =~ /$_->{regexp}/) {
                push @{$exits}, $self->{perfdata}->threshold_check(value => $options{value}, threshold => [ { label => $_->{label}, exit_litteral => $_->{threshold} } ]);
                $thresholds->{$_->{threshold}} = $self->{perfdata}->get_perfdata_for_output(label => $_->{label});

            }
        }
        $status = $self->{output}->get_most_critical(status => $exits) if (scalar(@{$exits}) > 0);
    }
    
    return ($status, $thresholds->{warning}, $thresholds->{critical});
}

sub get_severity {
    my ($self, %options) = @_;
    my $status = 'UNKNOWN'; # default 
    
    if (defined($self->{overload_th}->{$options{section}})) {
        foreach (@{$self->{overload_th}->{$options{section}}}) {            
            if ($options{value} =~ /$_->{filter}/i) {
                $status = $_->{status};
                return $status;
            }
        }
    }
    foreach (@{$thresholds->{$options{section}}}) {           
        if ($options{value} =~ /$$_[0]/i) {
            $status = $$_[1];
            return $status;
        }
    }
    
    return $status;
}

1;

__END__

=head1 MODE

Check components (Fans, Power Supplies, Temperatures, Disks, Nvram Batteries).

=over 8

=item B<--component>

Which component to check (Default: 'all').
Can be: 'psu', 'fan', 'disk', 'temperature', 'battery'.

=item B<--exclude>

Exclude some parts (comma seperated list) (Example: --exclude=psu)
Can also exclude specific instance: --exclude='psu#3.3#'

=item B<--absent-problem>

Return an error if an entity is not 'present' (default is skipping) (comma seperated list)
Can be specific or global: --absent-problem=fan#1.1#

=item B<--no-component>

Return an error if no compenents are checked.
If total (with skipped) is 0. (Default: 'critical' returns).

=item B<--threshold-overload>

Set to overload default threshold values (syntax: section,status,regexp)
It used before default thresholds (order stays).
Example: --threshold-overload='fan,CRITICAL,^(?!(ok)$)'

=item B<--warning>

Set warning threshold for temperatures (syntax: regexp,treshold)
Example: --warning='.*,20'

=item B<--critical>

Set critical threshold for temperatures and battery charge (syntax: type,regexp,treshold)
Example: --critical='temperature,1.1,25' --critical='battery,.*,20:'

=back

=cut
    
