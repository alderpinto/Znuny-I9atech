# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
#               2018-2020 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::API::Util;

use strict;
use warnings;
no warnings 'redefine';

use utf8;

use Date::Parse;

use vars qw(@ISA);

our @ObjectDependencies = ();

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    $Self->{LayoutObject} = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    $Self->{ConfigObject} = $Kernel::OM->Get('Kernel::Config');

    return $Self;
}

sub CleanJSON {
    my ( $Self, %Param ) = @_;

    my $JSON = $Self->{LayoutObject}->JSONEncode( Data => $Param{ Data });
    my $NumberFields = $Kernel::OM->Get('Kernel::Config')
      ->Get('RS::API::ObjectType')->{Number};

    my $NumsStr = join '|', @{ $NumberFields };

    $JSON =~ s/("($NumsStr)"\s*:\s*)"(\-?\d+\.?\d*)"/$1$3/xg;

    return $JSON;
}

# Получить токен для отправки уведомлений на мобильное приложение
sub GetUserToken {
    my ( $Self, %Param ) = @_;

    return unless defined $Param{UserID};

    return if !$Self->IsMobilePackageInstalled;

    my $TokenRows = $Kernel::OM->Get('Kernel::System::DB')->SelectAll(
        SQL => qq{
            SELECT token
            FROM RS_user_push_token
            WHERE user_id = ?
        },
        Bind => [ \$Param{UserID} ]
    ) // [];

    if ( @{ $TokenRows } ) {
        return $TokenRows->[0][0];
    }

    return;
}

sub IsMobilePackageInstalled {
    my ( $Self, %Param ) = @_;

    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');

    my $CacheResult = $CacheObject->Get(
        Type => 'Mobile',
        Key   => 'IsMobilePackageInstalled'
    );

    return $CacheResult if $CacheResult;

    my $IsInstalled = $Kernel::OM->Get('Kernel::System::Package')->PackageIsInstalled(
        Name   => 'RS4OTRS_Mobile'
    );

    $CacheObject->Set(
        Type  => 'Mobile',
        Key   => 'IsMobilePackageInstalled',
        Value => $IsInstalled,
        TTL   => 60 * 60 * 24 * 30, # 30 дней
    );

    return $IsInstalled;
}

sub IsAdvancedTicketSearchInstalled {
    my ( $Self, %Param ) = @_;

    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');

    my $CacheResult = $CacheObject->Get(
        Type => 'API',
        Key   => 'IsAdvancedTicketSearchInstalled'
    );

    return $CacheResult if $CacheResult;

    my @PackageList = $Kernel::OM->Get('Kernel::System::Package')
      ->RepositoryList( Result => 'short' );

    my $IsInstalled = 0;
    for my $Package (@PackageList) {
        if (    $Package->{Name} eq 'RS4OTRS_AdvancedTicketSearch'
            and $Package->{Status} eq 'installed'
            and version->parse( $Package->{Version} ) >= version->parse('6.1.24') )
        {
            $IsInstalled = 1;
        }
    }

    $CacheObject->Set(
        Type  => 'API',
        Key   => 'IsAdvancedTicketSearchInstalled',
        Value => $IsInstalled,
        TTL   => 60 * 60 * 24 * 30, # 30 дней
    );

    return $IsInstalled;
}

1;
