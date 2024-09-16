# --
# Copyright (C) 2001-2018 OTRS AG, http://otrs.com/
#               2021 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.tx
# --

package Kernel::Modules::AgentMobileTicketStatus;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
        Content     => '{}',
        Type        => 'inline',
        NoCache     => 1,
    );  
}

1;
