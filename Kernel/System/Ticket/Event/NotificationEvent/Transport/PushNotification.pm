# --
# Copyright (C) 2001-2018 OTRS AG, http://otrs.com/
#               2020 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.tx
# --

package Kernel::System::Ticket::Event::NotificationEvent::Transport::PushNotification;
## nofilter(TidyAll::Plugin::OTRS::Perl::LayoutObject)
## nofilter(TidyAll::Plugin::OTRS::Perl::ParamObject)

use strict;
use warnings;
no warnings 'redefine';

use Data::Dumper;

use Kernel::System::VariableCheck qw(:all);

use Kernel::System::EventHandler;

use base qw(
    Kernel::System::Ticket::Event::NotificationEvent::Transport::Base
    Kernel::System::EventHandler
);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::Email',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::Queue',
    'Kernel::System::SystemAddress',
    'Kernel::System::Ticket',
    'Kernel::System::User',
    'Kernel::System::Web::Request',
);

=head1 NAME

Kernel::System::Ticket::Event::NotificationEvent::Transport::Email - email transport layer

=head1 SYNOPSIS

Notification event transport layer.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create a notification transport object. Do not use it directly, instead use:

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new('');
    my $TransportObject = $Kernel::OM->Get('Kernel::System::Ticket::Event::NotificationEvent::Transport::Email');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    $Self->EventHandlerInit(
        Config => 'Ticket::EventModulePost',
    );

    return $Self;
}

sub SendNotification {
    my ( $Self, %Param ) = @_;

    for my $Needed (qw(TicketID UserID Notification Recipient)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => 'Need $Needed!',
            );
            return;
        }
    }
    my $RecipientID = $Param{Recipient}{UserID};

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my %Notification = %{ $Param{Notification} };

    $Notification{Body} = $Kernel::OM->Get('Kernel::System::HTMLUtils')
                          ->ToAscii( String => $Notification{Body} );

    my $UtilObject = $Kernel::OM->Get('Kernel::System::API::Util');

#    for my $RecipientID ( @{ $Notification{Data}{RecipientAgents} } ) {

        my $Token = $UtilObject->GetUserToken( UserID => $RecipientID );

#        next unless $Token;
        return unless $Token;

        $Self->EventHandler(
            Event => 'PushEvent',
            Data => {
                Event    => 'PushEvent',
                UserID   => $RecipientID,
                Subject  => $Notification{Subject},
                Body     => $Notification{Body},
                Token    => $Token,
                Server   => $ConfigObject->Get('FQDN') // '',
                TicketID => $Param{TicketID}
            },
            UserID => 1
        );
#    }

    return 1;
}

sub GetTransportRecipients {
    my ( $Self, %Param ) = @_;

    return ();
}

sub TransportSettingsDisplayGet {
    my ( $Self, %Param ) = @_;

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # generate HTML
    my $Output = $LayoutObject->Output(
        TemplateFile => 'AdminNotificationEventTransportPushSettings',
        Data         => \%Param,
    );

    return $Output;
}

sub TransportParamSettingsGet {
    my ( $Self, %Param ) = @_;

    for my $Needed (qw(GetParam)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed",
            );
        }
    }

    # get param object
=a
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');

    PARAMETER:
    for my $Parameter (qw(RecipientPhoneNumber)) {
        my @Data = $ParamObject->GetArray( Param => $Parameter );
        next PARAMETER if !@Data;
        $Param{GetParam}->{Data}->{$Parameter} = \@Data;
    }
=cut

    # Note: Example how to set errors and use them
    # on the normal AdminNotificationEvent screen
    # # set error
    # $Param{GetParam}->{$Parameter.'ServerError'} = 'ServerError';

    return 1;
}

sub IsUsable {
    my ( $Self, %Param ) = @_;

    # define if this transport is usable on
    # this specific moment
    return 1;
}

sub DESTROY {
    my $Self = shift;

    $Self->EventHandlerTransaction();

    return 1;
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

