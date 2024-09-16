# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
#               2018-2020 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Output::HTML::ZZZLayout_ChallengeTokenCheck;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(IsHashRefWithData);

our $ObjectManagerDisabled = 1;

{
    no warnings 'redefine';

sub Kernel::Output::HTML::Layout::ChallengeTokenCheck {
    my ( $Self, %Param ) = @_;

    # return if feature is disabled
    return 1 if !$Kernel::OM->Get('Kernel::Config')->Get('SessionCSRFProtection');

    # get challenge token and check it
    # RS
    my $ChallengeToken = $Kernel::OM->Get('Kernel::System::Web::Request')
        ->GetParam( Param => 'ChallengeToken' ) || $Param{ChallengeToken} || '';

    # check regular ChallengeToken
    return 1 if $ChallengeToken eq $Self->{UserChallengeToken};

    # check ChallengeToken of all own sessions
    my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');
    my @Sessions      = $SessionObject->GetAllSessionIDs();

    SESSION:
    for my $SessionID (@Sessions) {
        my %Data = $SessionObject->GetSessionIDData( SessionID => $SessionID );
        next SESSION if !$Data{UserID};
        next SESSION if $Data{UserID} ne $Self->{UserID};
        next SESSION if !$Data{UserChallengeToken};

        # check ChallengeToken
        return 1 if $ChallengeToken eq $Data{UserChallengeToken};
    }

    # RS
    if ( $Param{Silent} ) {
        return;
    }

    # no valid token found
    if ( $Param{Type} && lc $Param{Type} eq 'customer' ) {
        $Self->CustomerFatalError(
            Message => 'Invalid Challenge Token!',
        );
    }
    else {
        $Self->FatalError(
            Message => 'Invalid Challenge Token!',
        );
    }

    return;
}


}

1;
