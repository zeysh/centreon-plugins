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

package hardware::server::hp::bladechassis::snmp::mode::components::fan;

use strict;
use warnings;

my %map_conditions = (
    1 => 'other', 
    2 => 'ok', 
    3 => 'degraded', 
    4 => 'failed',
);

my %present_map = (
    1 => 'other',
    2 => 'absent',
    3 => 'present',
    4 => 'Weird!!!', # for blades it can return 4, which is NOT spesified in MIB
);

sub check {
    my ($self) = @_;

    $self->{components}->{fan} = {name => 'fans', total => 0, skip => 0};
    $self->{output}->output_add(long_msg => "Checking fans");
    return if ($self->check_exclude(section => 'fan'));
    
    my $oid_cpqRackCommonEnclosureFanPresent = '.1.3.6.1.4.1.232.22.2.3.1.3.1.8';
    my $oid_cpqRackCommonEnclosureFanIndex = '.1.3.6.1.4.1.232.22.2.3.1.3.1.3';
    my $oid_cpqRackCommonEnclosureFanPartNumber = '.1.3.6.1.4.1.232.22.2.3.1.3.1.6';
    my $oid_cpqRackCommonEnclosureFanSparePartNumber = '.1.3.6.1.4.1.232.22.2.3.1.3.1.7';
    my $oid_cpqRackCommonEnclosureFanCondition = '.1.3.6.1.4.1.232.22.2.3.1.3.1.11';
    
    my $result = $self->{snmp}->get_table(oid => $oid_cpqRackCommonEnclosureFanPresent);
    return if (scalar(keys %$result) <= 0);
    my @get_oids = ();
    my @oids_end = ();
    foreach my $key ($self->{snmp}->oid_lex_sort(keys %$result)) {
        $key =~ /\.([0-9]+)$/;
        my $oid_end = $1;
        
        next if ($present_map{$result->{$key}} ne 'present' && 
                 $self->absent_problem(section => 'fan', instance => $oid_end));
        
        push @oids_end, $oid_end;
        push @get_oids, $oid_cpqRackCommonEnclosureFanIndex . "." . $oid_end, $oid_cpqRackCommonEnclosureFanPartNumber . "." . $oid_end,
                $oid_cpqRackCommonEnclosureFanSparePartNumber . "." . $oid_end, $oid_cpqRackCommonEnclosureFanCondition . "." . $oid_end;
    }

    $result = $self->{snmp}->get_leef(oids => \@get_oids);
    foreach (@oids_end) {
        my $fan_index = $result->{$oid_cpqRackCommonEnclosureFanIndex . '.' . $_};
        my $fan_condition = $result->{$oid_cpqRackCommonEnclosureFanCondition . '.' . $_};
        my $fan_part = $result->{$oid_cpqRackCommonEnclosureFanPartNumber . '.' . $_};
        my $fan_spare = $result->{$oid_cpqRackCommonEnclosureFanSparePartNumber . '.' . $_};
        
        next if ($self->check_exclude(section => 'fan', instance => $fan_index));
        $self->{components}->{fan}->{total}++;
        $self->{output}->output_add(long_msg => sprintf("Fan %d condition is %s [part: %s, spare: %s].", 
                                    $fan_index, $map_conditions{$fan_condition},
                                    $fan_part, $fan_spare));
        my $exit = $self->get_severity(section => 'fan', value => $map_conditions{$fan_condition});
        if (!$self->{output}->is_status(value => $exit, compare => 'ok', litteral => 1)) {
            $self->{output}->output_add(severity => $exit,
                                        short_msg => sprintf("Fan %d condition is %s", $fan_index, $map_conditions{$fan_condition}));
        }
    }
}

1;