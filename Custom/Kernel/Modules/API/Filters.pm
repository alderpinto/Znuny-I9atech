# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
#               2018-2020 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::API::Filters;

use strict;
use warnings;
no warnings 'redefine';

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {%Param};
    bless( $Self, $Type );

    $Self->{Param} = \%Param;

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $APIFilterObject = $Kernel::OM->Get('Kernel::System::API::Filter');

    my $Subaction = $Self->{Subaction};

    my $Success = 0;
    my $Result = {};

    if ( $Subaction eq 'GetTicketViews' ) {

        $Result = $APIFilterObject->GetTicketViews(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } else {

        $Result = {
            Response => "ERROR",
            Message  => "Method doesn't exist"
        };
    }

    my $JSON = $Kernel::OM->Get('Kernel::System::API::Util')
               ->CleanJSON( Data => $Result );

    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
        Content     => $JSON,
        Type        => 'inline',
        NoCache     => 1,
    );
}

1;
