# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
#               2018-2020 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::API::Customer;

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

    $Self->{TicketObject}        = $Kernel::OM->Get('Kernel::System::Ticket');
    $Self->{CustomerUserObject}  = $Kernel::OM->Get('Kernel::System::CustomerUser');

    return $Self;
}

sub GetCustomerUserList {
    my ( $Self, %Param ) = @_;

    my $Search           = $Param{Search};
    my $UserLogin        = $Param{Login};
    my $PostMasterSearch = $Param{Email};
    my $CustomerID       = $Param{CustomerID};

    my %SearchParam = (
        ( $Param{Search} ? ( Search           => "*$Param{Search}*" ) : () ),
        ( $Param{Login}  ? ( UserLogin        => "*$Param{Login}*" )  : () ),
        ( $Param{Email}  ? ( PostMasterSearch => "$Param{Email}" )  : () ),
        ( $Param{CustomerID} ? ( CustomerID => "$Param{CustomerID}" ) : () ),
        ( $Param{Limit} ? ( Limit           => $Param{Limit} ) : () )
    );

    my $Result;
    my $CustomerUserObject = $Self->{CustomerUserObject};

    my @CustomerUsers = ();                                    

    my %CustomerUserList = $CustomerUserObject->CustomerSearch(
        ( %SearchParam ? (%SearchParam) : ( Search => '*', Limit => 100 ) ) );

    for my $CustomerUserLogin ( keys %CustomerUserList ) {
        my %CustomerUser = $CustomerUserObject->CustomerUserDataGet(
            User => $CustomerUserLogin
        );

        push @CustomerUsers,
          {
            CustomerID   => $CustomerUser{UserCustomerID} || undef,
            Email        => $CustomerUser{UserEmail}      || undef,
            Login        => $CustomerUser{UserLogin}      || undef,
            Firstname    => $CustomerUser{UserFirstname}  || 'Not defined',
            Lastname     => $CustomerUser{UserLastname}   || 'Not defined',
            Avatar =>
"http://www.sg-webs.com/wp-content/uploads/2014/12/Robert-Morris-Circle.png"
          }
    }

    $Result = {
        Response      => "OK",
        CustomerUsers => \@CustomerUsers
    };

    return $Result;
}

sub GetCustomerList {
    my ( $Self, %Param ) = @_;

    my $Result;
    my %CustomerCompanyList = $Kernel::OM->Get('Kernel::System::CustomerCompany')
                       ->CustomerCompanyList();

    my @CustomerCompanies = map {
        {
            CustomerID => $_,
            Name       => $CustomerCompanyList{$_},
        }
    } keys %CustomerCompanyList;

    $Result = {
        Response => "OK",
        CustomerCompanies => \@CustomerCompanies
    };

    return $Result;
}

sub GetCustomerUser {
    my ( $Self, %Param ) = @_;

    my $CustomerUserObject = $Self->{CustomerUserObject};

    if ( !$Param{CustomerUser} ) {
        return {
            Response => "ERROR",
            Message  => "No CustomerUser parameter"
        };
    }

    my %User = $CustomerUserObject->CustomerUserDataGet(
        User => $Param{CustomerUser},
    );

    if ( !%User ) {
        return {
            Response => "ERROR",
            Message  => "No CustomerUser"
        };
    }

    my %ResultUser = ();
    for (qw/
        UserFirstname
        UserLastname
        UserCustomerID
        UserLogin
        UserEmail
        UserCountry
        UserCity
        UserStreet
        UserZip
        UserPhone
        UserMobile
        UserFax
        UserTitle
        UserComment
        ValidID
        /) {

       $ResultUser{$_} = $User{$_} || undef;
    }

    return {
        Response => "OK",
        %ResultUser
    };
}

sub CreateCustomerUser {
    my ( $Self, %Param ) = @_;

    my $Result;
    my $CustomerUserObject = $Self->{CustomerUserObject};

    # Обязательные
    my @FailedRequiredParams = ();
    for ( qw/ Firstname Lastname CustomerID Login Email / ) {
        if ( !$Param{$_} ) {
            push @FailedRequiredParams, $_; 
        }            
    }

    if ( !@FailedRequiredParams ) {

        my $UserLogin = $CustomerUserObject->CustomerUserAdd(
            Source         => 'CustomerUser', # CustomerUser source config
            UserFirstname  => $Param{Firstname},
            UserLastname   => $Param{Lastname},
            UserCustomerID => $Param{CustomerID},
            UserLogin      => $Param{Login},
            ( $Param{Password} ?
                ( UserPassword => $Param{Password} ) : () ),
            UserEmail      => $Param{Email},

            ( $Param{Country} ?
                ( UserCountry => $Param{Country} ) : () ),
            ( $Param{City} ?
                ( UserCity => $Param{City} ) : () ),
            ( $Param{Street} ?
                ( UserStreet => $Param{Street} ) : () ),
            ( $Param{Zip} ?
                ( UserZip => $Param{Zip} ) : () ),
            ( $Param{Phone} ?
                ( UserPhone => $Param{Phone} ) : () ),
            ( $Param{Mobile} ?
                ( UserMobile => $Param{Mobile} ) : () ),
            ( $Param{Fax} ?
                ( UserFax => $Param{Fax} ) : () ),

            ( $Param{Title} ?
                ( UserTitle => $Param{Title} ) : () ),
            ( $Param{Comment} ?
                ( UserComment => $Param{Comment} ) : () ),

            ValidID => 1,
            UserID  => $Param{UserID}
        );

        if ( $UserLogin ) {

            if ( $Param{InterfaceLanguage} ) {
                $CustomerUserObject->SetPreferences(
                    Key    => 'UserLanguage',
                    Value  => $Param{InterfaceLanguage},
                    UserID => $UserLogin
                );
            }

            $Result = { Response => "OK" };

        } else {

            $Result = {
                Response => "ERROR",
                Message  => "Couldn't create customer user"
            };
        }

    } else {

        $Result = {
            Response => "ERROR",
            Message  => "Required fields is not defined: "
                        .join(", ", @FailedRequiredParams ) 
        };
    }

    return $Result;
}

1;
