# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
#               2018-2020 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::API::User;

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

    $Self->{UserObject} = $Kernel::OM->Get('Kernel::System::User');

    return $Self;
}

sub GetUserList {
    my ( $Self, %Param ) = @_;
    
    my $Result;

    my %Users = $Self->{UserObject}->UserList(
        Type  => 'Short',
        Valid => 1,
    );

    my @UserIDs = ();

    if ( $Param{QueueID} ) {

        my $GID = $Kernel::OM->Get('Kernel::System::Queue')
                    ->GetQueueGroupID( QueueID => $Param{QueueID} );

        my %MemberList = $Kernel::OM->Get('Kernel::System::Group')->PermissionGroupGet(
            GroupID => $GID,
            Type    => 'owner'
        );

        @UserIDs = keys %MemberList;

    } elsif ( $Param{ServiceID} ) {

    } else {

        @UserIDs = keys %Users;
    }

    my @Users = ();
    for my $UserID (@UserIDs) {
        my %User = $Self->{UserObject}->GetUserData( UserID => $UserID );            
        if ( %User ) {
            for my $Field (
                qw/UserAuthBackend UserCreateNextMask
                UserSystemConfigurationCategory UserTitle UserMobile/
              )
            {
                if ( defined $User{$Field} and $User{$Field} eq '' ) {
                    $User{$Field} = undef;
                }
            }

            push @Users, \%User;
        }
    }

    $Result = {
        Response => "OK",
        Users    => \@Users,
        Count    => scalar @Users
    };

    return $Result;
}

sub GetUserPermissions {
    my ( $Self, %Param ) = @_;

    my $Result;

    my $GroupsInfoRows = $Kernel::OM->Get('Kernel::System::DB')->SelectAll(
        SQL  => qq{
            SELECT gu.group_id, g.name group_name,
                   gu.permission_key, q.id queue_id,
                   q.name queue_name
            FROM group_user gu
            JOIN permission_groups g
                ON gu.group_id = g.id AND gu.user_id = ?
            LEFT JOIN queue q ON gu.group_id = q.group_id

            UNION

            SELECT gr.group_id, g.name group_name,
                   gr.permission_key, q.id queue_id,
                   q.name queue_name
            FROM group_role gr
            JOIN role_user ru ON gr.role_id = ru.role_id AND ru.user_id = ?
            JOIN permission_groups g
                ON gr.group_id = g.id
            LEFT JOIN queue q ON gr.group_id = q.group_id
        },
        Bind => [ \$Param{UserID}, \$Param{UserID} ]
    ) // [];

    my $GroupIndex = 0;
    my $GroupIDGroupsIndexMap = {};

    my $Groups = [];
    for my $GroupRow ( @{ $GroupsInfoRows } ) {
        my $GroupID          = $GroupRow->[0];
        my $GroupName        = $GroupRow->[1];
        my $GroupPermission  = $GroupRow->[2];
        my $QueueID          = $GroupRow->[3];
        my $QueueName        = $GroupRow->[4];

        my $Group = {
            ID     => $GroupID,
            Name   => $GroupName,
            Queues => []
        };

        my $GroupIndexInGroupsArr = $GroupIDGroupsIndexMap->{ $GroupID };
        if ( defined $GroupIndexInGroupsArr ) {

            my $Found = 0;
            for my $Perm ( @{ $Groups->[ $GroupIndexInGroupsArr ]->{Permissions} } ) {
                if ( $Perm eq $GroupPermission ) {
                    $Found = 1;
                    last;
                }
            }

            if ( !$Found ) {
                push @{ $Groups->[ $GroupIndexInGroupsArr ]->{Permissions} },
                     $GroupPermission;
            }

            if ( $QueueID ) {
                my $IsQueueFound = 0;
                for my $Queue ( @{ $Groups->[ $GroupIndexInGroupsArr ]->{Queues} } ) {
                    $IsQueueFound = 1 if $Queue->{ID} == $QueueID;
                }

                if ( !$IsQueueFound ) {
                    push @{ $Groups->[ $GroupIndexInGroupsArr ]->{Queues} }, {
                        ID   => $QueueID,
                        Name => $QueueName
                    };
                }
            }
        }
        else {

            if ( $QueueID ) {
                push @{ $Group->{Queues} }, {
                    ID   => $QueueID,
                    Name => $QueueName
                };
            }

            $Group->{Permissions} = [ $GroupPermission ];

            push @{ $Groups }, $Group;

            $GroupIDGroupsIndexMap->{ $GroupID } = $GroupIndex++;
        }
    }

    $Result = {
        Response => "OK",
        Groups   => $Groups
    };

    return $Result;
}

1;
