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

package network::citrix::netscaler::common::mode::hastate;

use base qw(centreon::plugins::mode);

use strict;
use warnings;

my $oid_haPeerState = '.1.3.6.1.4.1.5951.4.1.1.23.3.0';
my $oid_haCurState = '.1.3.6.1.4.1.5951.4.1.1.23.24.0';

my $thresholds = {
    peerstate => [
        ['standalone', 'OK'],
        ['primary', 'OK'],
        ['secondary', 'OK'],
        ['unknown', 'UNKNOWN'],
    ],
    hastate => [
        ['unknown', 'UNKNOWN'],
        ['down|partialFail|monitorFail|completeFail|partialFailSsl|routemonitorFail', 'CRITICAL'],
        ['init|up|monitorOk|dump|disabled', 'OK'],
    ],
};

my %map_hastate_status = (
    0 => 'unknown', 
    1 => 'init', 
    2 => 'down', 
    3 => 'up', 
    4 => 'partialFail', 
    5 => 'monitorFail', 
    6 => 'monitorOk', 
    7 => 'completeFail', 
    8 => 'dumb', 
    9 => 'disabled', 
    10 => 'partialFailSsl', 
    11 => 'routemonitorFail',
);

my %map_peerstate_status = (
    0 => 'standalone', 
    1 => 'primary', 
    2 => 'secondary', 
    3 => 'unknown', 
);

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                {
                                  "threshold-overload:s@"   => { name => 'threshold_overload' },
                                });
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);
    
    $self->{overload_th} = {};
    foreach my $val (@{$self->{option_results}->{threshold_overload}}) {
        if ($val !~ /^(.*?),(.*?),(.*)$/) {
            $self->{output}->add_option_msg(short_msg => "Wrong treshold-overload option '" . $val . "'.");
            $self->{output}->option_exit();
        }
        my ($section, $status, $filter) = ($1, $2, $3);
        if ($self->{output}->is_litteral_status(status => $status) == 0) {
            $self->{output}->add_option_msg(short_msg => "Wrong treshold-overload status '" . $val . "'.");
            $self->{output}->option_exit();
        }
        $self->{overload_th}->{$section} = [] if (!defined($self->{overload_th}->{$section}));
        push @{$self->{overload_th}->{$section}}, {filter => $filter, status => $status};
    }
}

sub run {
    my ($self, %options) = @_;
    # $options{snmp} = snmp object
    $self->{snmp} = $options{snmp};
    
    $self->{result} = $self->{snmp}->get_leef(oids => [$oid_haPeerState, $oid_haCurState], nothing_quit => 1);
    
    my $exit = $self->get_severity(section => 'peerstate', value => $map_peerstate_status{$self->{result}->{$oid_haPeerState}});
    $self->{output}->output_add(severity => $exit,
                                short_msg => sprintf("Peer State is '%s'", 
                                                     $map_peerstate_status{$self->{result}->{$oid_haPeerState}}
                                                    )
                                );
    $exit = $self->get_severity(section => 'hastate', value => $map_hastate_status{$self->{result}->{$oid_haCurState}});
    $self->{output}->output_add(severity => $exit,
                                short_msg => sprintf("High Availibility Status is '%s'", 
                                                     $map_hastate_status{$self->{result}->{$oid_haCurState}}
                                                    )
                                );

    $self->{output}->display();
    $self->{output}->exit();
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

Check High Availability Status.

=over 8

=item B<--threshold-overload>

Set to overload default threshold values (syntax: section,status,regexp).
It used before default thresholds (order stays).
Example: --threshold-overload='hastate,CRITICAL,^(?!(up)$)'

=back

=cut
    