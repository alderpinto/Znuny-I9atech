# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
#               2018-2020 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::API::Service;

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

sub GetServiceList {
    my ( $Self, %Param ) = @_;
    
    my $Result;

    my %ServiceList;

    my @ServiceArr  = ();
    my @ServiceTree = ();

    if ( $Param{ CustomerUserLogin } ) {
        my $Tree        = [];
        my %ServiceChilds = ();

        my %Services = $Kernel::OM->Get('Kernel::System::Service')->ServiceList(
            UserID => $Param{UserID}
        );

        %ServiceList = $Kernel::OM->Get('Kernel::System::Service')->CustomerUserServiceMemberList(
            CustomerUserLogin => $Param{ CustomerUserLogin },
            Result            => 'HASH',
            DefaultServices   => 1
        );

        my %ServicesReverse = reverse %Services;

        for my $Service ( sort keys %ServicesReverse ) {
            my @SubServices = split '::', $Service;

            if ( @SubServices == 1 ) {
                push @{$Tree},
                  {
                    Name       => $SubServices[-1],
                    FullName   => $Service,
                    Childs     => [],
                    ID         => $ServicesReverse{$Service},
                    Accessible => $ServiceList{ $ServicesReverse{$Service} } ? 1 : 0
                  };

                $ServiceChilds{$Service} = $Tree->[-1]{Childs};
                next;
            }

            my $Parent = join '::', @SubServices[ 0 .. $#SubServices - 1 ];
            push @{ $ServiceChilds{$Parent} },
              {
                Name       => $SubServices[-1],
                FullName   => $Service,
                Childs     => [],
                ID         => $ServicesReverse{$Service},
                Accessible => $ServiceList{ $ServicesReverse{$Service} } ? 1 : 0
              };

            $ServiceChilds{$Service} = $ServiceChilds{$Parent}->[-1]{Childs};
        }

        for my $Node ( @{$Tree} ) {
            $Kernel::OM->Get('Kernel::System::API::Queue')
              ->_TraverseTree( $Node, \@ServiceTree, \@ServiceArr );
        }

        return {
            Response  => "OK",
            Services    => \@ServiceArr,
            ServiceTree => \@ServiceTree
        };

    } else {

        %ServiceList = $Kernel::OM->Get('Kernel::System::Service')->ServiceList(
            UserID => $Param{UserID}
        );
    }

    my @Services = map {
        { ID => $_, Title => $ServiceList{$_}  }
    } keys %ServiceList;

    $Result = {
        Response => "OK",
        Services => \@Services
    };

    return $Result;
}

1;
