# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
#               2018-2020 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::API::Tickets 0.07;

use strict;
use warnings;
no warnings 'redefine';

use Data::Dumper;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {%Param};
    bless( $Self, $Type );

    $Self->{Param} = \%Param;

    $Self->{LayoutObject} = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    my $APITicketObject = $Kernel::OM->Get('Kernel::System::API::Ticket');

    my $Subaction = $Self->{Subaction};

    my $Success = 0;
    my $Result = {};

    if ( $Subaction eq 'GetTicketList' ) {

        $Result = $APITicketObject->GetTicketList(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'GetTicket' ) {

        if ( $Self->{Param}->{CustomerGetTicket} ) {
            $Self->{Param}->{CustomerID} = $Self->{Param}->{UserCustomerID};
            $Self->{Param}->{CustomerUserID} = $Self->{UserID};
            $Self->{UserID} = "1";
        }          

        my %Ticket = $TicketObject->TicketGet(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );        

        $Result = {
            Response => "OK",
            Tickets => [\%Ticket],
        };

    } elsif ( $Subaction eq 'GetTicketDeep' ) {

        if ( $Self->{Param}->{CustomerGetTicket} ) {
            $Self->{Param}->{CustomerID} = $Self->{Param}->{UserCustomerID};
            $Self->{Param}->{CustomerUserID} = $Self->{UserID};
            $Self->{UserID} = "1";
        }          

        my %Ticket = $TicketObject->TicketDeepGet(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );        

        $Result = {
            Response => "OK",
            Tickets => [\%Ticket],
        };

    }  elsif ( $Subaction eq 'UpdateTitle' ) {

        $Result = $APITicketObject->UpdateTitle(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'UpdateQueue' ) {

        $Result = $APITicketObject->UpdateQueue(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'UpdateType' ) {

        $Result = $APITicketObject->UpdateType(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'UpdateService' ) {

        $Result = $APITicketObject->UpdateService(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'UpdateSLA' ) {

        $Result = $APITicketObject->UpdateSLA(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'UpdateCustomer' ) {

        $Result = $APITicketObject->UpdateCustomer(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'UpdatePendingTime' ) {

        $Result = $APITicketObject->UpdatePendingTime(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'UpdateLock' ) {

        $Result = $APITicketObject->UpdateLock(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'UpdateArchiveFlag' ) {

        $Result = $APITicketObject->UpdateArchiveFlag(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'UpdateState' ) {

        $Result = $APITicketObject->UpdateState(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'UpdateOwner' ) {

        if ( defined $Self->{Param}{NewUserID} and
             $Self->{Param}{NewUserID} == 0 ) {

            $Self->{Param}{NewUserID} = $Self->{UserID};
        }

        $Result = $APITicketObject->UpdateOwner(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    # TODO: refactoring elsif
    } elsif ( $Subaction eq 'UpdateResponsible' ) {

        $Result = $APITicketObject->UpdateResponsible(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'UpdatePriority' ) {

        $Result = $APITicketObject->UpdatePriority(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'MarkTicketAsSeen' ) {

        $Result = $APITicketObject->MarkTicketAsSeen(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'MarkArticleAsSeen' ) {

        $Result = $APITicketObject->MarkArticleAsSeen(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'GetArticles' ) {

        $Result = $APITicketObject->GetArticles(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'CreateTicket' ) {

        $Result = $APITicketObject->CreateTicket(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'CreateArticle' ) {

        $Result = $APITicketObject->CreateArticle(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'CreateAttachment' ) {

        $Result = $APITicketObject->CreateAttachment(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'GetAttachment' ) {

        $Result = $APITicketObject->GetAttachment(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

        if ( ref $Result ne 'HASH' ) {
            return $Result;
        }

    } elsif ( $Subaction eq 'GetAttachmentIndex' ) {

        $Result = $APITicketObject->GetAttachment(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

        if ( ref $Result ne 'HASH' ) {
            return $Result;
        }

    } elsif ( $Subaction eq 'WatchTicket' ) {

        $Result = $APITicketObject->WatchTicket(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } elsif ( $Subaction eq 'UpdateTicket' ) {

        $Result = $APITicketObject->UpdateTicket(
            %{ $Self->{Param} },
            UserID => $Self->{UserID}
        );

    } else {

        $Result = {
            Response => "ERROR",
            Message  => "Method doesn't exist"
        };
    }

    # Для всех однотипных запросов
    if ( $Success ) {
        $Result = { Response => "OK" };
    } elsif ( !keys %{ $Result } ) {
        $Result = { Response => "ERROR", Message => "Error while updating" };
    }

    my $JSON = $Kernel::OM->Get('Kernel::System::API::Util')
               ->CleanJSON( Data => $Result );

    return $Self->{LayoutObject}->Attachment(
        ContentType => 'application/json; charset=' . $Self->{LayoutObject}{Charset},
        Content     => $JSON,
        Type        => 'inline',
        NoCache     => 1,
    );
}

1;
