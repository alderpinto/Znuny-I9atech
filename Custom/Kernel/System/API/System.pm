# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
#               2018-2020 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::API::System;

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
    $Self->{DFObject}   = $Kernel::OM->Get('Kernel::System::DynamicField');
    $Self->{UtilObject} = $Kernel::OM->Get('Kernel::System::API::Util');

    return $Self;
}

sub GetPackageList {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my @Packages = $Kernel::OM->Get('Kernel::System::Package')->RepositoryList(
        Result => 'Short'
    );

    my @Result = ();
    for my $Package ( @Packages ) {
        if ( $Package->{Name} =~ /^RS4OTRS_(API|Mobile)$/x ) {
            delete $Package->{MD5sum};
            delete $Package->{Status};
            delete $Package->{Vendor};

            push @Result, $Package;
        }
    }

    return {
        Response => "OK",
        Packages => \@Result
    };
}

sub GetDynamicFieldList {
    my ( $Self, %Param ) = @_;

    my $ScreenDynamicFields = $Kernel::OM->Get('Kernel::Config')
                     ->Get("RS:API::Ticket::MobileScreen::DynamicFields");

    my $List = $Self->{DFObject}->DynamicFieldListGet();

    my %Result = ();
    for my $Field ( @{$List} ) {

        my %Screens = ();
        for my $Screen ( sort keys %{$ScreenDynamicFields} ) {
            if ( exists $ScreenDynamicFields->{$Screen}{$Field->{Name}} ) {
                $Screens{$Screen} =
                  $ScreenDynamicFields->{$Screen}{$Field->{Name}};
            }
        }

        push @{ $Result{ $Field->{ObjectType} } },
          {
            ID         => $Field->{ID},
            Name       => $Field->{Name},
            Label      => $Field->{Label},
            FieldType  => $Field->{FieldType},
            ObjectType => $Field->{ObjectType},
            Screens    => \%Screens,
            Config     => {
                (
                    $Field->{Config}{PossibleValues}
                    ? ( PossibleValues => $Field->{Config}{PossibleValues} )
                    : ()
                )
            }
          };
    }

    return {
        Response      => "OK",
        DynamicFields => \%Result
    };
}

1;
