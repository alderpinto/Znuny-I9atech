# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
#               2018-2020 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::API::Filter;

use strict;
use warnings;
no warnings 'redefine';

use utf8;

use vars qw(@ISA);

our @ObjectDependencies = ();

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    $Self->{ConfigObject} = $Kernel::OM->Get('Kernel::Config');
    $Self->{TicketObject} = $Kernel::OM->Get('Kernel::System::Ticket');

    return $Self;
}

sub GetTicketViews {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    
    my $Result;

    my $DefaultState = $ConfigObject->Get('RS::API::DefaultState') || 'new';
    $DefaultState = '_nostate_' unless $Param{QueueID}; # уже непосредственно для фильтрации

    my %Restricted_AgentMobileTicketNote_States   = ();
    my %Restricted_AgentMobileNewTicket_States    = ();
    my %Restricted_AgentMobileTicketStatus_States = ();
    my %Restricted_AgentMobileTicketClose_States  = ();
    my %Restricted_AgentMobileEditTicket_States   = ();

    if ( $Param{QueueID} ) {
        if (
            defined $ConfigObject->Get("Ticket::Frontend::AgentMobileTicketNote")
              and ref $ConfigObject->Get("Ticket::Frontend::AgentMobileTicketNote") eq 'HASH'
              and ref $ConfigObject->Get("Ticket::Frontend::AgentMobileTicketNote")->{StateType} eq 'ARRAY'
            )
        {
            %Restricted_AgentMobileTicketNote_States = $Self->{TicketObject}->TicketStateList(
                Action  => 'AgentMobileTicketNote',
                QueueID => $Param{QueueID},
                UserID  => $Param{UserID}
            );
            %Restricted_AgentMobileTicketNote_States = reverse %Restricted_AgentMobileTicketNote_States;
        }

        if (
            defined $ConfigObject->Get("Ticket::Frontend::AgentMobileNewTicket")
              and ref $ConfigObject->Get("Ticket::Frontend::AgentMobileNewTicket") eq 'HASH'
              and ref $ConfigObject->Get("Ticket::Frontend::AgentMobileNewTicket")->{StateType} eq 'ARRAY'
            )
        {
            %Restricted_AgentMobileNewTicket_States = $Self->{TicketObject}->TicketStateList(
                Action  => 'AgentMobileNewTicket',
                QueueID => $Param{QueueID},
                UserID  => $Param{UserID}
            );
            %Restricted_AgentMobileNewTicket_States = reverse %Restricted_AgentMobileNewTicket_States;
        }

        if (
            defined $ConfigObject->Get("Ticket::Frontend::AgentMobileTicketStatus")
              and ref $ConfigObject->Get("Ticket::Frontend::AgentMobileTicketStatus") eq 'HASH'
              and ref $ConfigObject->Get("Ticket::Frontend::AgentMobileTicketStatus")->{StateType} eq 'ARRAY'
            )
        {
            %Restricted_AgentMobileTicketStatus_States = $Self->{TicketObject}->TicketStateList(
                Action  => 'AgentMobileTicketStatus',
                QueueID => $Param{QueueID},
                UserID  => $Param{UserID}
            );
            %Restricted_AgentMobileTicketStatus_States = reverse %Restricted_AgentMobileTicketStatus_States;
        }

        if (
            defined $ConfigObject->Get("Ticket::Frontend::AgentMobileTicketClose")
              and ref $ConfigObject->Get("Ticket::Frontend::AgentMobileTicketClose") eq 'HASH'
              and ref $ConfigObject->Get("Ticket::Frontend::AgentMobileTicketClose")->{StateType} eq 'ARRAY'
            )
        {
            %Restricted_AgentMobileTicketClose_States = $Self->{TicketObject}->TicketStateList(
                Action  => 'AgentMobileTicketClose',
                QueueID => $Param{QueueID},
                UserID  => $Param{UserID}
            );
            %Restricted_AgentMobileTicketClose_States = reverse %Restricted_AgentMobileTicketClose_States;
        }

        if (
            defined $ConfigObject->Get("Ticket::Frontend::AgentMobileEditTicket")
              and ref $ConfigObject->Get("Ticket::Frontend::AgentMobileEditTicket") eq 'HASH'
              and ref $ConfigObject->Get("Ticket::Frontend::AgentMobileEditTicket")->{StateType} eq 'ARRAY'
            )
        {
            %Restricted_AgentMobileEditTicket_States = $Self->{TicketObject}->TicketStateList(
                Action  => 'AgentMobileEditTicket',
                QueueID => $Param{QueueID},
                UserID  => $Param{UserID}
            );
            %Restricted_AgentMobileEditTicket_States = reverse %Restricted_AgentMobileEditTicket_States;
        }
    }

    my %Priorities = $Kernel::OM->Get('Kernel::System::Priority')->PriorityList(); 
    my %Types      = $Kernel::OM->Get('Kernel::System::Type')->TypeList(); 

    my $StateObject = $Kernel::OM->Get('Kernel::System::State');
    my %States     = $StateObject->StateList( UserID => $Param{UserID} );

    my %ViewableStateList = $StateObject->StateGetStatesByType(
        Type   => 'Viewable',
        Result => 'HASH'
    );

    my $StateTypeRows = $Kernel::OM->Get('Kernel::System::DB')->SelectAll(
        SQL => qq{
            SELECT ts.id, ts.name, ts.comments, tt.name, tt.comments
            FROM ticket_state ts
            JOIN ticket_state_type tt
                ON ts.type_id = tt.id
        },
        Bind => []
    ) // [];

    my $StateInfoHash = {};
    for my $Row ( @{ $StateTypeRows } ) {
        $StateInfoHash->{ $Row->[0] } = {
            StateName     => $Row->[1],
            StateTypeName => $Row->[3]
        }
    }

    my $PriorityColors = $ConfigObject->Get('RS::Mobile::Priority::Color')
      // { DEFAULT => '#ffffff' };
    my $StateColors = $ConfigObject->Get('RS::Mobile::State::Color')
      // { DEFAULT => '#ffffff' };
    my $TypeColors = $ConfigObject->Get('RS::Mobile::Type::Color')
      // { DEFAULT => '#ffffff' };

    my $StateBackgroundColors =
      $ConfigObject->Get('RS::Mobile::State::BackgroundColor')
      // { DEFAULT => '#ffffff' };
    my $TypeBackgroundColors =
      $ConfigObject->Get('RS::Mobile::Type::BackgroundColor')
      // { DEFAULT => '#ffffff' };

    my $TypeAbbr = $ConfigObject->Get('RS::Mobile::Type::Abbr') // {};

    my $AgentTicketPhoneConfig = $ConfigObject
                                 ->Get('Ticket::Frontend::AgentTicketPhone');

    my %PriorityReverse = reverse %Priorities;
    my @Priorities = map {
        {
            ID    => $PriorityReverse{$_},
            Name  => $_,
            Color => ( $PriorityColors->{ $_ }
                ? $PriorityColors->{ $_ }
                : $PriorityColors->{ DEFAULT } ),
            Default => ( $AgentTicketPhoneConfig->{Priority} eq $_ ? 1 : 0 )
        }
    } sort values %Priorities;

    my @Types = map {
        {
            ID    => $_,
            Name  => $Types{ $_ },

            Abbr  => ( $TypeAbbr->{ $Types{ $_ } }
                ? $TypeAbbr->{ $Types{ $_ } }
                : uc substr( ( $Types{ $_ } =~ s/\s+//gr ), 0, 3 ) ),

            Color => ( $TypeColors->{ $Types{ $_ } }
                ? $TypeColors->{ $Types{ $_ } }
                : $TypeColors->{ DEFAULT } ),

            BackgroundColor => ( $TypeBackgroundColors->{ $Types{ $_ } }
                ? $TypeBackgroundColors->{ $Types{ $_ } }
                : $TypeBackgroundColors->{ DEFAULT } )
        }
    } keys %Types;

    my %StateReverse = reverse %States;
    my @States = ();

    for my $StateName ( sort values %States ) {

        my %Screens;

        if ( $Restricted_AgentMobileTicketNote_States{ $StateName } or $StateName eq $DefaultState ) {
            $Screens{AgentMobileTicketNote} = 1;
        }
        if ( $Restricted_AgentMobileNewTicket_States{ $StateName } ) {
            $Screens{AgentMobileNewTicket} = 1;
        }
        if ( $Restricted_AgentMobileTicketClose_States{ $StateName } ) {
            $Screens{AgentMobileTicketClose} = 1;
        }
        if ( $Restricted_AgentMobileTicketStatus_States{ $StateName } ) {
            $Screens{AgentMobileTicketStatus} = 1;
        }
        if ( $Restricted_AgentMobileEditTicket_States{ $StateName } ) {
            $Screens{AgentMobileEditTicket} = 1;
        }

        push @States, {
            ID    => $StateReverse{ $StateName },
            Name  => $StateName,
            Default => $StateName eq $DefaultState ? 1 : 0,
            IsVisible => ( $ViewableStateList{ $StateReverse{ $StateName } } ? 1 : 0 ), # StateType: Open, Closed
            StateType => $StateInfoHash->{ $StateReverse{ $StateName } }->{StateTypeName},
            OnTicketCreateScreen => (
                ( $Restricted_AgentMobileTicketStatus_States{ $StateName } or $StateName eq $DefaultState ) ? 1 : 0
            ),
            Color => ( $StateColors->{$StateName}
                ? $StateColors->{$StateName}
                : $StateColors->{ DEFAULT } ),
            BackgroundColor => ( $StateBackgroundColors->{$StateName}
                ? $StateBackgroundColors->{$StateName}
                : $StateBackgroundColors->{ DEFAULT } ),
            Screens => \%Screens
        };
    }

    my $PossibleParams = [
        {
            Name      => "View",
            Exclusive => 1,
            Items     => [
                {
                  ID      => -1,
                  Name    => "Assigned to me",
                  Default => 1
                },
                {
                  ID   => -2,
                  Name => "My Queues"
                },
                {
                  ID   => -3,
                  Name => "Open"
                },
                {
                  ID   => -4,
                  Name => "Closed"
                },
                {
                  ID   => -5,
                  Name => "New notes"
                },
                {
                  ID   => -6,
                  Name => "My locked"
                },
                {
                  ID   => -7,
                  Name => "My watched"
                }
            ]
        },
        {
            Name  => 'Priority',
            Items => \@Priorities
        },
        {
            Name  => 'Type',
            Items => \@Types
        },
        {
            Name  => 'State',
            Items => \@States
        },
        {
          Name      => "Sort",
          Exclusive => 1,
          Items => [
            {
              Value => "EscalationSolutionTime",
              Name  => "By time to done"
            },
            {
              Value => "Age",
              Name  => "By creating date"
            },
            {
              Value => "Priority",
              Name  => "By priority"
            },
            {
              Value => "Changed",
              Name  => "By last update"
            }
          ]
        }
    ];


    if ( $Kernel::OM->Get('Kernel::System::Main')
           ->Require("Kernel::System::TicketViews", Silent => 1) ) {

        my $TicketViewsList = $Kernel::OM->Get('Kernel::System::TicketViews')->TicketViewsList(
            UserID  => $Param{UserID},
            ValidID => 1
        );

        for ( keys %{ $TicketViewsList } ) {
            push @{ $PossibleParams->[0]{Items} }, {
                ID   => $TicketViewsList->{$_}->{ID},
                Name => $TicketViewsList->{$_}->{Title}
            } 
        }
    }

    $Result = {
        Response => "OK",
        Groups   => $PossibleParams
    };

    return $Result;
}

1;
