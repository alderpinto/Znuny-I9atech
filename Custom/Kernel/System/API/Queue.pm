# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
#               2018-2020 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::API::Queue 0.03;

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

sub GetQueueList {
    my ( $Self, %Param ) = @_;

    # We need to get Queues array with all accessible Queues and with every
    # ancestors of ones even if an agent has not group permissions to them.
    my @QueueArr = ();

    # Also we need to make QueueTree for them.
    my @QueueTree = ();

    my $Result;
    my $QueueObject = $Kernel::OM->Get('Kernel::System::Queue');

    # Get all possible valid queues from OTRS.
    # $VAR1 = {
    #                              Group name     RO
    #    '1' => 'Postmaster',      # postmaster   1
    #    '4' => 'Misc',            # users        0
    #    '3' => 'Junk',            # users        0
    #    '2' => 'Raw',             # users        0 <--- must be in the result list
    #    '5' => 'Raw::Raw_Child'   # stats        1
    # };
    my %AllQueues = $QueueObject->QueueList( Valid => 1 );

    # Reverse the taken hash in order to get access to a queue by its Queue name
    my %QueuesReverse = reverse %AllQueues;

    # Permissions: RO, RW
    my %UserQueues = $QueueObject->GetAllQueues( UserID => $Param{UserID} );

    # Permissions: CREATE
    if ( $Param{ForCreateTicket} ) {
        my %UserQueuesTypeCreate = $Kernel::OM->Get('Kernel::System::Queue')
          ->GetAllQueues( UserID => $Param{UserID}, Type => 'create' );

        %UserQueues = ( %UserQueues, %UserQueuesTypeCreate );
    }

    # MOVE_INTO
    if ( $Param{ForUpdateQueue} ) {
        my %UserQueuesTypeCreate = $Kernel::OM->Get('Kernel::System::Queue')
          ->GetAllQueues( UserID => $Param{UserID}, Type => 'move_into' );

        %UserQueues = ( %UserQueues, %UserQueuesTypeCreate );
    }

    my $Tree        = [];
    my %QueueChilds = ();

    # Make Tree for every valid Queue
    for my $Queue ( sort keys %QueuesReverse ) {

        my @SubQueues = split '::', $Queue;

        if ( @SubQueues == 1 ) {
            push @{$Tree},
              {
                Name       => $SubQueues[-1],
                FullName   => $Queue,
                Childs     => [],
                ID         => $QueuesReverse{$Queue},
                Accessible => $UserQueues{ $QueuesReverse{$Queue} } ? 1 : 0
              };
            $QueueChilds{$Queue} = $Tree->[-1]{Childs};
            next;
        }

        my $Parent = join '::', @SubQueues[ 0 .. $#SubQueues - 1 ];
        push @{ $QueueChilds{$Parent} },
          {
            Name       => $SubQueues[-1],
            FullName   => $Queue,
            Childs     => [],
            ID         => $QueuesReverse{$Queue},
            Accessible => $UserQueues{ $QueuesReverse{$Queue} } ? 1 : 0
          };
        $QueueChilds{$Queue} = $QueueChilds{$Parent}->[-1]{Childs};
    }

    # Traverse the taken tree and remove all not accessible nodes and
    # their not accessible parent nodes, getting a new @QueueTree and
    # @QueueArr. All Queues has additional field Accessible 1|0
    for my $Node ( @{$Tree} ) {

        # Add child which is accessible or has accessible ones
        $Self->_TraverseTree( $Node, \@QueueTree, \@QueueArr );
    }

    $Result = {
        Response  => "OK",
        Queues    => \@QueueArr,
        QueueTree => \@QueueTree
    };

    return $Result;
}

sub _HasAccessibleChild {
    my ( $Self, $Node ) = @_;

    for my $Child ( @{ $Node->{Childs} } ) {
        return $Child->{Accessible} ? 1 : $Self->_HasAccessibleChild($Child);
    }

    return;
}

sub _TraverseTree {
    my ( $Self, $Node, $NewTree, $QueueArr ) = @_;

    my $ChildCount = @{ $Node->{Childs} };

    my $AtLeastOne = $Self->_HasAccessibleChild( $Node );

    if ( $Node->{Accessible} or $AtLeastOne ) {
        push @{$NewTree},
          {
            Name       => $Node->{Name},
            FullName   => $Node->{FullName},
            Childs     => [],
            ID         => $Node->{ID},
            Accessible => $Node->{Accessible}
          };
        $NewTree = $NewTree->[-1]{Childs};

        # For common array of necessary queues
        push @{$QueueArr},
          {
            ID         => $Node->{ID},
            Name       => $Node->{Name},
            FullName   => $Node->{FullName},
            Accessible => $Node->{Accessible}
          };
    }

    for my $Child ( @{ $Node->{Childs} } ) {
        $Self->_TraverseTree( $Child, $NewTree, $QueueArr );
    }
}

1;

__END__

=head1 METHODS

=over

=item GetQueueList

Get queue list for a defined user.

    my $QueuesInfo = APIQueueObject->GetQueueList(
        ForCreateTicket => 1|0   # optional
        UserID          => $UserID
    );

It returns Queues for Groups with RO or RW permissions.

If C<ForCreateTicket> is passed then Queues from Groups with CREATE
permission also will be returned.

Returns:

    {
        "Queues": [{
            "ID": 5,
            "Name": "Management Queue"
            "FullName": "Management Queue"
        }],
        "QueueTree": [{
            "ID": 5,
            "Childs": [],
            "Name": "Management Queue",
            "FullName": "Management Queue"
        }],
        Response  => $Response,
    }

=back
