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

package storage::netapp::mode::cpstatistics;

use base qw(centreon::plugins::mode);

use strict;
use warnings;
use centreon::plugins::statefile;
use centreon::plugins::values;

my $maps_counters = {
    timer   => { class => 'centreon::plugins::values', obj => undef,
                set => {
                        key_values => [ { name => 'timer', diff => 1 }, ],
                        output_template => 'CP timer : %s',
                        perfdatas => [
                            { value => 'timer_absolute', template => '%d', min => 0 },
                        ],
                    }
               },
    snapshot   => { class => 'centreon::plugins::values', obj => undef,
                set => {
                        key_values => [ { name => 'snapshot', diff => 1 }, ],
                        output_template => 'CP snapshot : %s',
                        perfdatas => [
                            { value => 'snapshot_absolute', template => '%d', min => 0 },
                        ],
                    }
               },
    lowerwater   => { class => 'centreon::plugins::values', obj => undef,
                set => {
                        key_values => [ { name => 'lowerwater', diff => 1 }, ],
                        output_template => 'CP low water mark : %s',
                        perfdatas => [
                            { value => 'lowerwater_absolute', template => '%d', min => 0 },
                        ],
                    }
               },
    highwater   => { class => 'centreon::plugins::values', obj => undef,
                set => {
                        key_values => [ { name => 'highwater', diff => 1 }, ],
                        output_template => 'CP high water mark : %s',
                        perfdatas => [
                            { value => 'highwater_absolute', template => '%d', min => 0 },
                        ],
                    }
               },
    logfull   => { class => 'centreon::plugins::values', obj => undef,
                set => {
                        key_values => [ { name => 'logfull', diff => 1 }, ],
                        output_template => 'CP nv-log full : %s',
                        perfdatas => [
                            { value => 'logfull_absolute', template => '%d', min => 0 },
                        ],
                    }
               },
    back   => { class => 'centreon::plugins::values', obj => undef,
                set => {
                        key_values => [ { name => 'back', diff => 1 }, ],
                        output_template => 'CP back-to-back : %s',
                        perfdatas => [
                            { value => 'back_absolute', template => '%d', min => 0 },
                        ],
                    }
               },
    flush   => { class => 'centreon::plugins::values', obj => undef,
                set => {
                        key_values => [ { name => 'flush', diff => 1 }, ],
                        output_template => 'CP flush unlogged write data : %s',
                        perfdatas => [
                            { value => 'flush_absolute', template => '%d', min => 0 },
                        ],
                    }
               },
    sync   => { class => 'centreon::plugins::values', obj => undef,
                set => {
                        key_values => [ { name => 'sync', diff => 1 }, ],
                        output_template => 'CP sync requests : %s',
                        perfdatas => [
                            { value => 'sync_absolute', template => '%d', min => 0 },
                        ],
                    }
               },
    lowvbuf   => { class => 'centreon::plugins::values', obj => undef,
                set => {
                        key_values => [ { name => 'lowvbuf', diff => 1 }, ],
                        output_template => 'CP low virtual buffers : %s',
                        perfdatas => [
                            { value => 'lowvbuf_absolute', template => '%d', min => 0 },
                        ],
                    }
               },
    deferred   => { class => 'centreon::plugins::values', obj => undef,
                set => {
                        key_values => [ { name => 'deferred', diff => 1 }, ],
                        output_template => 'CP deferred : %s',
                        perfdatas => [
                            { value => 'deferred_absolute', template => '%d', min => 0 },
                        ],
                    }
               },
    lowdatavecs   => { class => 'centreon::plugins::values', obj => undef,
                set => {
                        key_values => [ { name => 'lowdatavecs', diff => 1 }, ],
                        output_template => 'CP low datavecs : %s',
                        perfdatas => [
                            { value => 'lowdatavecs_absolute', template => '%d', min => 0 },
                        ],
                    }
               },
};

my $oid_cpFromTimerOps = '.1.3.6.1.4.1.789.1.2.6.2.0';
my $oid_cpFromSnapshotOps = '.1.3.6.1.4.1.789.1.2.6.3.0';
my $oid_cpFromLowWaterOps = '.1.3.6.1.4.1.789.1.2.6.4.0';
my $oid_cpFromHighWaterOps = '.1.3.6.1.4.1.789.1.2.6.5.0';
my $oid_cpFromLogFullOps = '.1.3.6.1.4.1.789.1.2.6.6.0';
my $oid_cpFromCpOps = '.1.3.6.1.4.1.789.1.2.6.7.0';
my $oid_cpTotalOps = '.1.3.6.1.4.1.789.1.2.6.8.0';
my $oid_cpFromFlushOps = '.1.3.6.1.4.1.789.1.2.6.9.0';
my $oid_cpFromSyncOps = '.1.3.6.1.4.1.789.1.2.6.10.0';
my $oid_cpFromLowVbufOps = '.1.3.6.1.4.1.789.1.2.6.11.0';
my $oid_cpFromCpDeferredOps = '.1.3.6.1.4.1.789.1.2.6.12.0';
my $oid_cpFromLowDatavecsOps = '.1.3.6.1.4.1.789.1.2.6.13.0';

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                {
                                });

    $self->{statefile_value} = centreon::plugins::statefile->new(%options);  
    foreach (keys %{$maps_counters}) {
        $options{options}->add_options(arguments => {
                                                     'warning-' . $_ . ':s'    => { name => 'warning-' . $_ },
                                                     'critical-' . $_ . ':s'    => { name => 'critical-' . $_ },
                                      });
        my $class = $maps_counters->{$_}->{class};
        $maps_counters->{$_}->{obj} = $class->new(statefile => $self->{statefile_value},
                                                  output => $self->{output}, perfdata => $self->{perfdata},
                                                  label => $_);
        $maps_counters->{$_}->{obj}->set(%{$maps_counters->{$_}->{set}});
    }
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);
    
    foreach (keys %{$maps_counters}) {
        $maps_counters->{$_}->{obj}->init(option_results => $self->{option_results});
    }
    
    $self->{statefile_value}->check_options(%options);
}

sub run {
    my ($self, %options) = @_;
    # $options{snmp} = snmp object
    $self->{snmp} = $options{snmp};
    $self->{hostname} = $self->{snmp}->get_hostname();
    $self->{snmp_port} = $self->{snmp}->get_port();

    $self->manage_selection();
    
    $self->{new_datas} = {};
    $self->{statefile_value}->read(statefile => "cache_netapp_" . $self->{hostname}  . '_' . $self->{snmp_port} . '_' . $self->{mode});
    $self->{new_datas}->{last_timestamp} = time();
    
    $self->{output}->output_add(severity => 'OK',
                                short_msg => 'All CP statistics are ok');
    
    my ($short_msg, $short_msg_append, $long_msg, $long_msg_append) = ('', '', '', '');
    my @exits;
    foreach (sort keys %{$maps_counters}) {
        $maps_counters->{$_}->{obj}->set(instance => 'global');
    
        my ($value_check) = $maps_counters->{$_}->{obj}->execute(values => $self->{global},
                                                                 new_datas => $self->{new_datas});

        if ($value_check != 0) {
            $long_msg .= $long_msg_append . $maps_counters->{$_}->{obj}->output_error();
            $long_msg_append = ', ';
            next;
        }
        my $exit2 = $maps_counters->{$_}->{obj}->threshold_check();
        push @exits, $exit2;

        my $output = $maps_counters->{$_}->{obj}->output();
        $long_msg .= $long_msg_append . $output;
        $long_msg_append = ', ';
        
        if (!$self->{output}->is_status(litteral => 1, value => $exit2, compare => 'ok')) {
            $short_msg .= $short_msg_append . $output;
            $short_msg_append = ', ';
        }
        
        $self->{output}->output_add(long_msg => $output);
        $maps_counters->{$_}->{obj}->perfdata();
    }

    my $exit = $self->{output}->get_most_critical(status => [ @exits ]);
    if (!$self->{output}->is_status(litteral => 1, value => $exit, compare => 'ok')) {
        $self->{output}->output_add(severity => $exit,
                                    short_msg => "$short_msg"
                                    );
    }
    
    $self->{statefile_value}->write(data => $self->{new_datas});
    $self->{output}->display();
    $self->{output}->exit();
}

sub manage_selection {
    my ($self, %options) = @_;
    
    my $request = [$oid_cpFromTimerOps, $oid_cpFromSnapshotOps,
                   $oid_cpFromLowWaterOps, $oid_cpFromHighWaterOps,
                   $oid_cpFromLogFullOps, $oid_cpFromCpOps,
                   $oid_cpTotalOps, $oid_cpFromFlushOps,
                   $oid_cpFromSyncOps, $oid_cpFromLowVbufOps,
                   $oid_cpFromCpDeferredOps, $oid_cpFromLowDatavecsOps];
    
    $self->{results} = $self->{snmp}->get_leef(oids => $request, nothing_quit => 1);
    
    $self->{global} = {};
    $self->{global}->{timer} = defined($self->{results}->{$oid_cpFromTimerOps}) ? $self->{results}->{$oid_cpFromTimerOps} : 0;
    $self->{global}->{snapshot} = defined($self->{results}->{$oid_cpFromSnapshotOps}) ? $self->{results}->{$oid_cpFromSnapshotOps} : 0;
    $self->{global}->{lowerwater} = defined($self->{results}->{$oid_cpFromLowWaterOps}) ? $self->{results}->{$oid_cpFromLowWaterOps} : 0;
    $self->{global}->{highwater} = defined($self->{results}->{$oid_cpFromHighWaterOps}) ? $self->{results}->{$oid_cpFromHighWaterOps} : 0;
    $self->{global}->{logfull} = defined($self->{results}->{$oid_cpFromLogFullOps}) ? $self->{results}->{$oid_cpFromLogFullOps} : 0;
    $self->{global}->{back} = defined($self->{results}->{$oid_cpFromCpOps}) ? $self->{results}->{$oid_cpFromCpOps} : 0;
    $self->{global}->{flush} = defined($self->{results}->{$oid_cpFromFlushOps}) ? $self->{results}->{$oid_cpFromFlushOps} : 0;
    $self->{global}->{sync} = defined($self->{results}->{$oid_cpFromSyncOps}) ? $self->{results}->{$oid_cpFromSyncOps} : 0;
    $self->{global}->{lowvbuf} = defined($self->{results}->{$oid_cpFromLowVbufOps}) ? $self->{results}->{$oid_cpFromLowVbufOps} : 0;
    $self->{global}->{deferred} = defined($self->{results}->{$oid_cpFromCpDeferredOps}) ? $self->{results}->{$oid_cpFromCpDeferredOps} : 0;
    $self->{global}->{lowdatavecs} = defined($self->{results}->{$oid_cpFromLowDatavecsOps}) ? $self->{results}->{$oid_cpFromLowDatavecsOps} : 0;
}

1;

__END__

=head1 MODE

Check consistency point metrics.

=over 8

=item B<--warning-*>

Threshold warning.
Can be: 'timer', 'snapshot', 'lowerwater', 'highwater', 
'logfull', 'back', 'flush', 'sync', 'lowvbuf', 'deferred', 'lowdatavecs'.

=item B<--critical-*>

Threshold critical.
Can be: 'timer', 'snapshot', 'lowerwater', 'highwater', 
'logfull', 'back', 'flush', 'sync', 'lowvbuf', 'deferred', 'lowdatavecs'.

=back

=cut
    