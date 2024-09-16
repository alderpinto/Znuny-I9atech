# --
# Copyright (C) 2001-2018 OTRS AG, http://otrs.com/
#               2020 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.tx
# --

package Kernel::GenericInterface::Invoker::RS::PushNotify;

use strict;
use warnings;

use Data::Dumper;

use base qw( Kernel::System::EventHandler );

# prevent 'Used once' warning for Kernel::OM
use Kernel::System::ObjectManager;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    $Self->EventHandlerInit(
        Config => 'Ticket::EventModulePost',
    );

    if ( !$Param{DebuggerObject} ) {
        return {
            Success      => 0,
            ErrorMessage => "Got no DebuggerObject!"
        };
    }

    $Self->{DebuggerObject}   = $Param{DebuggerObject};

    return $Self;
}

sub PrepareRequest {
    my ( $Self, %Param ) = @_;

    if ( $Param{Data}{Event} eq 'PushEvent' ) {

        return {
            Success => 1,
            Data    => {
                data => {
                    title     => $Param{Data}{Subject},
                    detail    => $Param{Data}{Body},
                    server    => $Param{Data}{Server},
                    ticket_id => $Param{Data}{TicketID}
                },
                to => $Param{Data}{Token}
            }
        };
    }

    return {
        Success => 1,
        Data    => $Param{Data}
    };
}

sub HandleResponse {
    my ( $Self, %Param ) = @_;

    my $DynFieldBack = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');

    if ( !$Param{ResponseSuccess} ) {
        if ( !IsStringWithData( $Param{ResponseErrorMessage} ) ) {

            return $Self->{DebuggerObject}->Error(
                Summary => 'Got response error, but no response error message!',
            );
        }

        return {
            Success      => 0,
            ErrorMessage => $Param{ResponseErrorMessage},
        };
    }

    if ( $Param{Data}{failure} ) {
        $Kernel::OM->Get('Kernel::System::API::Setting')
            ->UpdateFailedNotificationCount(
                Token => $Param{Data}{_RequestData}{to}
            );
    }

    return {
        Success => 1,
        Data    => $Param{Data}
    };
}

sub DESTROY {
    my $Self = shift;

    $Self->EventHandlerTransaction();

    return 1;
}

1;
