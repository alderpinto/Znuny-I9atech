# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
#               2018-2020 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::API::SLA;

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

    return $Self;
}

sub GetSLAList {
    my ( $Self, %Param ) = @_;
    
    my $Result;

    my %SLAList = $Kernel::OM->Get('Kernel::System::SLA')->SLAList(
        ( $Param{ ServiceID } ?
            ( ServiceID => $Param{ ServiceID } ) : () ),
        UserID    => $Param{UserID}
    );

    my @SLAList = map {
        { ID => $_, Title => $SLAList{$_}  }
    } keys %SLAList;

    $Result = {
        Response => "OK",
        SLAList  => \@SLAList
    };

    return $Result;
}

1;
