# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
#               2018-2020 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::API::Setting;

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

    $Self->{DBObject}   = $Kernel::OM->Get('Kernel::System::DB');
    $Self->{UtilObject} = $Kernel::OM->Get('Kernel::System::API::Util');

    return $Self;
}

sub GetLanguageList {
    my ( $Self, %Param ) = @_;
    
    my $Result;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my %DefaultUsedLanguages = %{ $ConfigObject->Get('DefaultUsedLanguages') || {} };
    my %DefaultUsedLanguagesNative = %{ $ConfigObject->Get('DefaultUsedLanguagesNative') || {} };

    my %Languages;
    LANGUAGEID:
    for my $LanguageID ( sort keys %DefaultUsedLanguages ) {

        # next language if there is not set any name for current language
        if ( !$DefaultUsedLanguages{$LanguageID} && !$DefaultUsedLanguagesNative{$LanguageID} ) {
            next LANGUAGEID;
        }

        # get texts in native and default language
        my $Text        = $DefaultUsedLanguagesNative{$LanguageID} || '';
        my $TextEnglish = $DefaultUsedLanguages{$LanguageID}       || '';

        # translate to current user's language
        my $TextTranslated =
            $Kernel::OM->Get('Kernel::Output::HTML::Layout')->{LanguageObject}->Translate($TextEnglish);

        if ( $TextTranslated && $TextTranslated ne $Text ) {
            $Text .= ' - ' . $TextTranslated;
        }

        # next language if there is not set English nor native name of language.
        next LANGUAGEID if !$Text;

        $Languages{$LanguageID} = $Text;
    }        

    my @Languages = map { { ID => $_, Name => $Languages{$_} } } keys %Languages;

    $Result = {
        Response  => "OK",
        Languages => \@Languages
    };

    return $Result;
}

sub UpdateFailedNotificationCount {
    my ( $Self, %Param ) = @_;

    return if !$Self->{UtilObject}->IsMobilePackageInstalled;

    my $Rows = $Kernel::OM->Get('Kernel::System::DB')->SelectAll(
        SQL   => qq{
            SELECT failed_count, token, added_date, user_id
            FROM RS_user_push_token
            WHERE token = ?
        },
        Bind  => [ \$Param{Token} ],
        Limit => 1
    ) // [];

    return unless @{ $Rows };

    my $FailedCount = $Rows->[0][0];
    $FailedCount++;

    # Токен уже не торт
    if ( $FailedCount >= 3 ) {
        $Kernel::OM->Get('Kernel::System::DB')->Do(
            SQL  => qq{
                DELETE FROM RS_user_push_token
                WHERE token = ?
            },
            Bind => [ \$Param{Token} ]
        );

        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "PushToken '$Rows->[0][1]', "
                ."added '$Rows->[0][2]' for UserID "
                ."'$Rows->[0][3]' was removed as invalid!"
        );

    } else {

        $Kernel::OM->Get('Kernel::System::DB')->Do(
            SQL  => qq{
                UPDATE RS_user_push_token
                SET failed_count = ?
                WHERE token = ?
            },
            Bind => [ \$FailedCount, \$Param{Token} ]
        );
    }

    return;
}

sub SetPushNotificationToken {
    my ( $Self, %Param ) = @_;

    if ( !$Self->{UtilObject}->IsMobilePackageInstalled ) {
        return {
            Response => "ERROR",
            Message  => "RS4OTRS_Mobile package must be installed!"
        };
    }

    if ( !$Param{Token} ) {
        return {
            Response => "ERROR",
            Message  => "Token cannot be empty"
        };
    }
    
    $Self->{DBObject}->Do(
        SQL  => 'DELETE FROM RS_user_push_token WHERE user_id = ?',
        Bind => [ \$Param{UserID} ]
    );

    $Self->{DBObject}->Do(
        SQL => qq{
            INSERT INTO RS_user_push_token (user_id, token, added_date, added_by)
            VALUES (?, ?, current_timestamp, 1)
        },
        Bind => [ \$Param{UserID}, \$Param{Token} ]
    );

    return {
        Response => "OK"
    };
}

1;
