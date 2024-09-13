# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
#               2018-2020 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::API::Ticket;

use strict;
use warnings;
no warnings 'redefine';

use utf8;

use Date::Parse;
use POSIX qw/strftime/;
use MIME::Base64 qw/decode_base64/;

use vars qw(@ISA);

our @ObjectDependencies = ();

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    $Self->{TicketObject}  = $Kernel::OM->Get('Kernel::System::Ticket');
    $Self->{GroupObject}   = $Kernel::OM->Get('Kernel::System::Group');
    $Self->{UtilObject}    = $Kernel::OM->Get('Kernel::System::API::Util');
    $Self->{ArticleObject} = $Kernel::OM->Get('Kernel::System::Ticket::Article');

    return $Self;
}

sub SetDynamicFieldValue {
    my ( $Self, %Param ) = @_;

    my $DynamicFieldName  = $Param{Name};
    my $DynamicFieldValue = $Param{Value};
    my $TicketID          = $Param{TicketID};

    if (   not defined $DynamicFieldName
        or not defined $DynamicFieldValue )
    {
        return;
    }

    my $DynamicFieldConfig = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldGet(
        Name => $DynamicFieldName
    );
    my $DynamicFieldBackend = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');

    my $SuccessDynamicFieldSet = $DynamicFieldBackend->ValueSet(
        DynamicFieldConfig => $DynamicFieldConfig,
        ObjectID           => $TicketID,
        Value              => $DynamicFieldValue,
        UserID             => 1,

        NoEventNotify      => $Param{NoEventNotify}
    );

    if ( !$SuccessDynamicFieldSet ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Cannot set dynamic field '$DynamicFieldName' "
                        ."for TicketID: $TicketID"
        );
        return;
    }

    return 1;
}

sub _GetViewParams {
    my ( $Self, %Param ) = @_;

    my %ViewParams = (
        -1 => {
            OwnerIDs => [ $Param{ UserID } ],
            StateType => 'Open'
        },

        -2 => {
            StateType => 'Open'
        },

        -3 => {
            StateType => 'Open'
        },

        -4 => {
            StateType => 'Closed'
        },

        -5 => {
            NotTicketFlag => {
                Seen => 1
            }
        },

        -6 => {
            OwnerIDs => [ $Param{ UserID } ],
            Locks    => [ 'lock' ]
        },

        -7 => {
            WatchUserIDs => [ $Param{ UserID } ]
        }
    );

    if ( $Param{ ViewID } < 0 ) {
        if ( exists $ViewParams{ $Param{ ViewID } } ) {

            # TODO: change to variable name
            if ( $Param{ViewID} == -2 ) {
                my $QueueRows =
                  $Kernel::OM->Get('Kernel::System::DB')->SelectAll(
                    SQL =>
                      q{SELECT queue_id FROM personal_queues WHERE user_id = ?},
                    Bind => [ \$Param{UserID} ]
                  );

                my @Queues = ();
                for my $Row ( @{ $QueueRows } ) {
                    push @Queues, $Row->[0];
                }

                if ( @Queues ) {
                    $ViewParams{ $Param{ ViewID } }{QueueIDs} = \@Queues;
                }
            }

            return [ $ViewParams{ $Param{ ViewID } } ];
        }

    } else {

        if ( $Kernel::OM->Get('Kernel::System::Main')
               ->Require("Kernel::System::TicketViews", Silent => 1) ) {

            my $TicketView = $Kernel::OM->Get('Kernel::System::TicketViews')->TicketViewsGet(
                ID => $Param{ ViewID }
            );

            my $Config = $Kernel::OM->Get('Kernel::Config')
                             ->Get("Ticket::Frontend::AgentTicketViews");

            my $SortBy = $Param{SortBy}
                || $TicketView->{SortBy}
                || $Config->{'SortBy::Default'}
                || 'Age';

            my $OrderBy = $Param{OrderBy}
                 || $TicketView->{OrderBy}
                 || $Config->{'Order::Default'}
                 || 'Up';

            my @Filters = $Kernel::OM->Get('Kernel::System::TicketViews')->FilterForTicketSearch(
                ID         => $TicketView->{ID},
                UserID     => $Param{ UserID },
                OrderBy    => $OrderBy,
                SortBy     => $SortBy,
                Permission => 'ro',
            );

            return \@Filters;
        }
    }

    return [];
}

sub _GetTicketRequestParams {
    my ( $Self, %Param ) = @_;

    my $ViewParams = [];

    # Получаем параметры для TicketSearch из Видов (фильтров)
    if ( $Param{ ViewID } ) {
        $ViewParams = $Self->_GetViewParams(
            ViewID => $Param{ ViewID },
            UserID => $Param{ UserID },

            SortBy  => $Param{SortBy},
            OrderBy => $Param{OrderBy}
        );

        for my $View ( @{ $ViewParams } ) {

            if ( $Param{SortBy} and $View->{SortBy} ) {
                $Param{SortBy}  .= ','.$View->{SortBy};
            } elsif ( $View->{SortBy} ) {
                $Param{SortBy}  = $View->{SortBy};
            }

            if ( $Param{OrderBy} and $View->{OrderBy} ) {
                $Param{OrderBy}  .= ','.$View->{OrderBy};
            } elsif ( $View->{OrderBy} ) {
                $Param{OrderBy}  = $View->{OrderBy};
            }
        }
    }

    my $AgentTicketSearchConfig = $Kernel::OM
        ->Get('Kernel::Config')
        ->Get('Ticket::Frontend::AgentTicketSearch');

    $Param{SortBy}  //= $AgentTicketSearchConfig->{'SortBy::Default'} // '';
    $Param{OrderBy} //= $AgentTicketSearchConfig->{'Order::Default'}  // '';

    my $SortBy  =  [ split( ',', $Param{SortBy}  ) ];
    my $OrderBy =  [ split( ',', $Param{OrderBy} ) ];

    # Если явно не указано, то новые вверху
    if ( ( $Param{SortBy} // '' ) !~ /Age/ ) {
        push @{ $SortBy },  'Age';
        push @{ $OrderBy }, 'Down';
    }

    # Рассматриваем числа в FullTextSearch, как возможные значения для
    # TicketNumber
    # ---
    my $FullTextSearchCopy = $Param{FullTextSearch} // '';
    $FullTextSearchCopy =~ s/%//g;

    my $TicketNumberFromFullTextSearch = 0;
    if ( $FullTextSearchCopy =~ /^\d+$/ ) {
        $TicketNumberFromFullTextSearch = $FullTextSearchCopy;
    }
    # ---

    my %TicketParam = (
        ( $Param{FullTextSearch}
            ? ( MIMEBase_Subject => $Param{FullTextSearch},
                MIMEBase_Body    => $Param{FullTextSearch},
                MIMEBase_From    => $Param{FullTextSearch},
                MIMEBase_To      => $Param{FullTextSearch},
                MIMEBase_Cc      => $Param{FullTextSearch},
                ContentSearch => 'OR' )
            : () ),

        (
            $TicketNumberFromFullTextSearch
            ? ( TicketNumberFromFullTextSearch =>
                  $TicketNumberFromFullTextSearch )
            : ()
          ),

        SortBy  => $SortBy,
        OrderBy => $OrderBy,

        Result => $Param{ ResultType },

        ( $Param{TicketID} ?
            ( TicketID => $Param{TicketID} ) : () ),

        ( $Param{TicketNumber} ?
            ( TicketNumber => $Param{TicketNumber} ) : () ),

        ( $Param{Title} ?
            ( Title => $Param{Title} ) : () ),

        ( $Param{Queues} ?
            ( Queues => [ split ',', $Param{Queues} ] ) : () ),

        ( $Param{QueueIDs} ?
            ( QueueIDs => [ split ',', $Param{QueueIDs} ] ) : () ),

        ( $Param{Types} ?
            ( Types => [ split ',', $Param{Types} ] ) : () ),

        ( $Param{TypeIDs} ?
            ( TypeIDs => [ split ',', $Param{TypeIDs} ] ) : () ),

        ( $Param{States} ?
            ( States => [ split ',', $Param{States} ] ) : () ),

        # TODO:
        ( $Param{StateIDs} ?
            ( StateIDs => [ split ',', $Param{StateIDs} ] ) : () ),

        ( $Param{StateType} ?
            ( StateType => $Param{StateType} ) : () ),

        ( $Param{Priorities} ?
            ( Priorities => [ split ',', $Param{Priorities} ] ) : () ),

        ( $Param{PriorityIDs}    ? ( PriorityIDs => [ split ',', $Param{PriorityIDs} ] ) : () ),
        ( $Param{Services} ?
            ( Services => [ split ',', $Param{Services} ] ) : () ),

        ( $Param{ServiceIDs} ?
            ( ServiceIDs => [ split ',', $Param{ServiceIDs} ] ) : () ),

        ( $Param{SLAs} ?
            ( SLAs => [ split ',', $Param{SLAs} ] ) : () ),

        ( $Param{SLAIDs} ?
            ( SLAIDs => [ split ',', $Param{SLAIDs} ] ) : () ),

        ( $Param{Locks} ?
            ( Locks => [ split ',', $Param{Locks} ] ) : () ),

        ( $Param{LockIDs} ?
            ( LockIDs => [ split ',', $Param{LockIDs} ] ) : () ),

        ( $Param{OwnerIDs} ?
            ( OwnerIDs => [ split ',', $Param{OwnerIDs} ] ) : () ),

        ( $Param{ResponsibleIDs} ?
            ( ResponsibleIDs => [ split ',', $Param{ResponsibleIDs} ] ) : () ),

        ( $Param{WatchUserIDs} ?
            ( WatchUserIDs => [ split ',', $Param{WatchUserIDs} ] ) : () ),

        ( $Param{CustomerID} ?
            ( CustomerID => $Param{CustomerID} ) : () ),

        ( $Param{CustomerUserLogin} ?
            ( CustomerUserLogin => $Param{CustomerUserLogin} ) : () ),

        ( $Param{From} ?
            ( From => $Param{From} ) : () ),

        ( $Param{To} ?
            ( To => $Param{To} ) : () ),

        ( $Param{Cc} ?
            ( Cc => $Param{Cc} ) : () ),

        ( $Param{Subject} ?
            ( Subject => $Param{Subject} ) : () ),

        ( $Param{Body} ?
            ( Body => $Param{Body} ) : () ),

        UserID => $Param{UserID}
    );

    return {
        ViewParams  => $ViewParams,
        TicketParam => \%TicketParam
    };
}

sub UpdatePendingTime {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Self->{TicketObject};

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    my $HasPermission = $Self->_CheckGroupPermission(
        QueueID => $Ticket{QueueID},
        UserID  => $Param{UserID}
    );

    if ( !$HasPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    my %User = $Kernel::OM->Get('Kernel::System::User')->GetUserData(
        UserID => $Param{UserID}
    );

    my $DateTimeObject;
    if ( $Param{UntilTimeDateUnix} ) {
        $DateTimeObject = $Kernel::OM->Create(
            'Kernel::System::DateTime',
            ObjectParams => {
                Epoch => $Param{ UntilTimeDateUnix }
            }
        );
    }
    elsif ( $Param{Year} ) {
        $DateTimeObject = $Kernel::OM->Create(
            'Kernel::System::DateTime',
            ObjectParams => {
                Year     => $Param{Year},
                Month    => $Param{Month},
                Day      => $Param{Day},
                Hour     => $Param{Hour},
                Minute   => $Param{Minute},
                TimeZone => $User{UserTimeZone}
            }
        );
    }

    if ( $DateTimeObject ) {
        $DateTimeObject->ToOTRSTimeZone();

        my $Success = $TicketObject->TicketPendingTimeSet(
            String   => $DateTimeObject->ToString,
            TicketID => $Param{TicketID},
            UserID   => $Param{UserID}
        );

        if ( !$Success ) {
            return {
                Response => 'ERROR',
                Message  => 'Cannot update PendingTime'
            };
        }
    }

    return { Response => 'OK' };
}

sub _UpdateTicket {
    my ( $Self, %Param ) = @_;

    $Param{Rule} //= '';
    #TODO: add detailed information about errors from Update.. methods

    my @FailedUpdatedItems = ();

    my $TicketObject = $Self->{TicketObject};

    my $HasRWPermission = $Self->_CheckGroupPermission(
        QueueID => $Param{Ticket}{QueueID},
        UserID  => $Param{UserID}
    );

    if ( $Param{Title} and $Param{Title} ne $Param{Ticket}{Title} ) {
        if ( $HasRWPermission ) {
            my $Success = $TicketObject->TicketTitleUpdate(
                Title    => $Param{Title},
                TicketID => $Param{TicketID},
                UserID   => $Param{UserID}
            );

            if ( !$Success ) {
                push @FailedUpdatedItems, 'Title';
            }
        }
        else {
            push @FailedUpdatedItems, 'Title';
        }
    }

    if (   ( $Param{Queue} and $Param{Queue} ne $Param{Ticket}{Queue} )
        or ( $Param{QueueID} and $Param{QueueID} != $Param{Ticket}{QueueID} ) )
    {

        if ( $Param{Queue} and !$Param{QueueID} ) {
            $Param{QueueID} = $Kernel::OM->Get('Kernel::System::Queue')
              ->QueueLookup( Queue => $Param{Queue} );
        }

        my $HasMoveIntoPermission = $Self->_CheckGroupPermission(
            QueueID => $Param{QueueID},
            Type    => ['move_into'],
            UserID  => $Param{UserID}
        );

        my $Success;

        if ( !$HasRWPermission and !$HasMoveIntoPermission ) {
            push @FailedUpdatedItems, 'Queue';
        }
        elsif ( $Param{Ticket}{Lock} eq 'unlock' ) {
            $Success = $TicketObject->TicketQueueSet(
                QueueID  => $Param{QueueID},
                TicketID => $Param{TicketID},
                UserID   => $Param{UserID}
            );

            if ( !$Success ) {
                push @FailedUpdatedItems, 'Queue';
            }
        }
        elsif ( $Param{Ticket}{Lock} eq 'lock' ) {

            if ( $Param{Ticket}{OwnerID} == $Param{UserID} ) {

                $Success = $TicketObject->TicketQueueSet(
                    QueueID  => $Param{QueueID},
                    TicketID => $Param{TicketID},
                    UserID   => $Param{UserID}
                );

                if ( !$Success ) {
                    push @FailedUpdatedItems, 'Queue';
                }
            }
            else {
                push @FailedUpdatedItems, 'Queue';
            }
        }
    }

    if (   ( $Param{Type} and $Param{Type} ne $Param{Ticket}{Type} )
        or ( $Param{TypeID} and $Param{TypeID} != $Param{Ticket}{TypeID} ) )
    {
        if ( $HasRWPermission ) {
            my $Success = $TicketObject->TicketTypeSet(
                Type     => $Param{Type},
                TypeID   => $Param{TypeID},
                TicketID => $Param{TicketID},
                UserID   => $Param{UserID}
            );

            if ( !$Success ) {
                push @FailedUpdatedItems, 'Type';
            }
        }
        else {
            push @FailedUpdatedItems, 'Type';
        }
    }

    if (   ( $Param{Service} and $Param{Service} ne $Param{Ticket}{Service} )
        or ( $Param{ServiceID} and $Param{ServiceID} != $Param{Ticket}{ServiceID} ) )
    {
        if ( $HasRWPermission ) {
            my $Success = $TicketObject->TicketServiceSet(
                Service   => $Param{Service},
                ServiceID => $Param{ServiceID},
                TicketID  => $Param{TicketID},
                UserID    => $Param{UserID}
            );

            if ( !$Success ) {
                push @FailedUpdatedItems, 'Service';
            }
        }
        else {
            push @FailedUpdatedItems, 'Service';
        }
    }

    if (   ( $Param{SLA} and $Param{SLA} ne $Param{Ticket}{SLA} )
        or ( $Param{SLAID} and $Param{SLAID} != $Param{Ticket}{SLAID} ) )
    {
        if ( $HasRWPermission ) {
            my $Success = $TicketObject->TicketSLASet(
                SLA       => $Param{SLA},
                SLAID     => $Param{SLAID},
                TicketID  => $Param{TicketID},
                UserID    => $Param{UserID}
            );

            if ( !$Success ) {
                push @FailedUpdatedItems, 'SLA';
            }
        }
        else {
            push @FailedUpdatedItems, 'SLA';
        }
    }

    if (   ( $Param{CustomerID} and $Param{CustomerID} ne $Param{Ticket}{CustomerID} )
        or ( $Param{CustomerUserID} and $Param{CustomerUserID} ne $Param{Ticket}{CustomerUserID} ) )
    {
        if ( $HasRWPermission ) {
            my $Success = $TicketObject->TicketCustomerSet(
                No       => $Param{CustomerID},
                User     => $Param{CustomerUserID},
                TicketID => $Param{TicketID},
                UserID   => $Param{UserID}
            );

            if ( !$Success ) {
                push @FailedUpdatedItems, 'Customer';
            }
        }
        else {
            push @FailedUpdatedItems, 'Customer';
        }
    }

    if (   ( $Param{Lock} and $Param{Lock} ne $Param{Ticket}{Lock} )
        or ( $Param{LockID} and $Param{LockID} != $Param{Ticket}{LockID} ) )
    {
        my $HasPermission = $Self->_CheckGroupPermission(
            QueueID => $Param{Ticket}{QueueID},
            Type    => [ 'ro', 'move_into', 'note', 'owner', 'priority' ],
            Op      => 'OR',
            UserID  => $Param{UserID}
        );

        my $Success = $TicketObject->TicketLockSet(
            Lock     => $Param{Lock},
            LockID   => $Param{LockID},
            TicketID => $Param{TicketID},
            UserID   => $Param{UserID}
        );

        if ( !$Success ) {
            push @FailedUpdatedItems, 'Lock';
        }
    }

    if ( $Param{ArchiveFlag} and $Param{ArchiveFlag} ne $Param{Ticket}{ArchiveFlag} ) {

        if ( $HasRWPermission ) {
            my $Success = $TicketObject->TicketArchiveFlagSet(
                ArchiveFlag => $Param{ArchiveFlag},
                TicketID    => $Param{TicketID},
                UserID      => $Param{UserID}
            );

            if ( !$Success ) {
                push @FailedUpdatedItems, 'ArchiveFlag';
            }
        }
        else {
            push @FailedUpdatedItems, 'ArchiveFlag';
        }
    }

    if (   ( $Param{State} and $Param{State} ne $Param{Ticket}{State} )
        or ( $Param{StateID} and $Param{StateID} != $Param{Ticket}{StateID} ) )
    {
        if ( $HasRWPermission ) {

            my $Success;

            if ( $Param{Ticket}{Lock} eq 'unlock' ) {
                $Success = $TicketObject->TicketStateSet(
                    State    => $Param{State},
                    StateID  => $Param{StateID},
                    TicketID => $Param{TicketID},
                    UserID   => $Param{UserID}
                );

                if ( !$Success ) {
                    push @FailedUpdatedItems, 'State';
                }
            }
            elsif ( $Param{Ticket}{Lock} eq 'lock' ) {
                if ( $Param{Ticket}{OwnerID} == $Param{UserID} ) {
                    $Success = $TicketObject->TicketStateSet(
                        State    => $Param{State},
                        StateID  => $Param{StateID},
                        TicketID => $Param{TicketID},
                        UserID   => $Param{UserID}
                    );

                    if ( !$Success ) {
                        my %Ticket = $TicketObject->TicketGet(
                            TicketID => $Param{TicketID},
                            UserID   => $Param{UserID}
                        );

                        if ( $Ticket{StateType} eq 'closed' ) {
                            # One Success var for actions
                            $Success = $TicketObject->TicketLockSet(
                                Lock     => 'unlock',
                                TicketID => $Param{TicketID},
                                UserID   => $Param{UserID}
                            );
                        }
                    }
                }
                else {
                    push @FailedUpdatedItems, 'State';
                }
            }
        }
        else {
            push @FailedUpdatedItems, 'State';
        }
    }

    if (   ( $Param{NewOwner} and $Param{NewOwner} ne $Param{Ticket}{NewOwner} )
        or ( $Param{NewOwnerID} and $Param{NewOwnerID} != $Param{Ticket}{NewOwnerID} ) )
    {
        my $HasOwnerPermission = $Self->_CheckGroupPermission(
            QueueID => $Param{Ticket}{QueueID},
            Type    => ['owner'],
            UserID  => $Param{UserID}
        );

        if ($HasOwnerPermission) {
            if ( defined $Param{NewOwnerID}
                and $Param{NewOwnerID} == 0 )
            {
                $Param{NewOwnerID} = $Param{UserID};
            }

            my $Success;
            if ( $Param{Ticket}{Lock} eq 'unlock' ) {
                $Success = $TicketObject->TicketOwnerSet(
                    NewUser   => $Param{NewOwner},
                    NewUserID => $Param{NewOwnerID},
                    TicketID  => $Param{TicketID},
                    UserID    => $Param{UserID}
                );
            }
            elsif ( $Param{Ticket}{Lock} eq 'lock' ) {
                if (   $Param{Ticket}{OwnerID} == $Param{UserID}
                    or $Param{Rule} eq 'TicketEdit' )
                {
                    $Success = $TicketObject->TicketOwnerSet(
                        NewUser   => $Param{NewOwner},
                        NewUserID => $Param{NewOwnerID},
                        TicketID  => $Param{TicketID},
                        UserID    => $Param{UserID}
                    );
                }
                else {
                    push @FailedUpdatedItems, 'Owner';
                }
            }

            if ( !$Success ) {
                push @FailedUpdatedItems, 'Owner';
            }
            else {

                # TODO: move to one function as updateOwner
                my $OwnerID = $Param{NewOwnerID};
                if ( !$OwnerID ) {
                    my %Ticket = $TicketObject->TicketGet(
                        TicketID => $Param{TicketID},
                        UserID   => $Param{UserID}
                    );
                    $OwnerID = $Ticket{OwnerID};
                }

                my $Success = $TicketObject->TicketLockSet(
                    Lock     => 'lock',
                    TicketID => $Param{TicketID},
                    UserID   => $OwnerID
                );

                if ( !$Success ) {
                    push @FailedUpdatedItems, 'Owner';
                }
            }
        }
        else {
            push @FailedUpdatedItems, 'Owner';
        }
    }

    if (
        (
                $Param{NewResponsibleUser}
            and $Param{NewResponsibleUser} ne $Param{Ticket}{NewResponsibleUser}
        )
        or (    $Param{NewResponsibleUserID}
            and $Param{NewResponsibleUserID} !=
            $Param{Ticket}{NewResponsibleUserID} )
      )
    {
        if ($HasRWPermission) {
            my $Success = $TicketObject->TicketResponsibleSet(
                NewUser   => $Param{NewResponsibleUser},
                NewUserID => $Param{NewResponsibleUserID},
                TicketID  => $Param{TicketID},
                UserID    => $Param{UserID}
            );

            if ( !$Success ) {
                push @FailedUpdatedItems, 'Responsible';
            }
        }
        else {
            push @FailedUpdatedItems, 'Responsible';
        }
    }

    if (   ( $Param{Priority} and $Param{Priority} ne $Param{Ticket}{Priority} )
        or ( $Param{PriorityID} and $Param{PriorityID} != $Param{Ticket}{PriorityID} ) )
    {
        my $HasPriorityPermission = $Self->_CheckGroupPermission(
            QueueID => $Param{Ticket}{QueueID},
            Type    => ['priority'],
            UserID  => $Param{UserID}
        );

        if ( $HasPriorityPermission ) {
            my $Success;

            if ( $Param{Ticket}{Lock} eq 'unlock' ) {

                $Success = $TicketObject->TicketPrioritySet(
                    Priority   => $Param{Priority},
                    PriorityID => $Param{PriorityID},
                    TicketID   => $Param{TicketID},
                    UserID     => $Param{UserID}
                );
            }
            elsif ( $Param{Ticket}{Lock} eq 'lock' ) {
                if ( $Param{Ticket}{OwnerID} == $Param{UserID} ) {

                    $Success = $TicketObject->TicketPrioritySet(
                        Priority   => $Param{Priority},
                        PriorityID => $Param{PriorityID},
                        TicketID   => $Param{TicketID},
                        UserID     => $Param{UserID}
                    );
                }
                else {
                    push @FailedUpdatedItems, 'Priority';
                }
            }

            if ( !$Success ) {
                push @FailedUpdatedItems, 'Priority';
            }
        }
        else {
            push @FailedUpdatedItems, 'Priority';
        }
    }

    if ( $Param{Year} or $Param{ UntilTimeDateUnix } ) {

        if ( $HasRWPermission ) {
            my %User = $Kernel::OM->Get('Kernel::System::User')->GetUserData(
                UserID => $Param{UserID}
            );

            my $DateTimeObject;
            if ( $Param{UntilTimeDateUnix} ) {
                $DateTimeObject = $Kernel::OM->Create(
                    'Kernel::System::DateTime',
                    ObjectParams => {
                        Epoch => $Param{ UntilTimeDateUnix }
                    }
                );
            }
            else {
                $DateTimeObject = $Kernel::OM->Create(
                    'Kernel::System::DateTime',
                    ObjectParams => {
                        Year     => $Param{Year},
                        Month    => $Param{Month},
                        Day      => $Param{Day},
                        Hour     => $Param{Hour},
                        Minute   => $Param{Minute},
                        TimeZone => $User{UserTimeZone}
                    }
                );
            }

            if ( $DateTimeObject ) {
                $DateTimeObject->ToOTRSTimeZone();

                my $Success = $TicketObject->TicketPendingTimeSet(
                    String   => $DateTimeObject->ToString,
                    TicketID => $Param{TicketID},
                    UserID   => $Param{UserID}
                );

                if ( !$Success ) {
                    push @FailedUpdatedItems, 'PendingTime';
                }
            }
            else {
                push @FailedUpdatedItems, 'PendingTime';
            }
        }
        else {
            push @FailedUpdatedItems, 'PendingTime';
        }
    }

    if ( $Param{DynamicFields} ) {

        for my $DynamicFieldName ( sort keys %{ $Param{DynamicFields} } ) {
            my $Success = $Self->SetDynamicFieldValue(
                Name     => $DynamicFieldName,
                Value    => $Param{DynamicFields}{$DynamicFieldName},
                TicketID => $Param{Ticket}{TicketID}
            );

            push @FailedUpdatedItems, 'DynamicField_'.$DynamicFieldName if !$Success;
        }
    }

    return @FailedUpdatedItems;
}

sub CreateTicket {
    my ( $Self, %Param ) = @_;

    my $Result;
    my $TicketObject = $Self->{TicketObject};

    my @FailedRequiredParams = ();

    # Обязательные
    for ( qw/ Title QueueID PriorityID Body / ) {
        if ( !$Param{$_} ) {
            push @FailedRequiredParams, $_;
        }
    }

    if ( @FailedRequiredParams ) {
        return {
            Response => "ERROR",
            Message  => "Required fields is not defined: "
                        .join(", ", @FailedRequiredParams )
        };
    }

    my $GroupID = $Kernel::OM->Get('Kernel::System::Queue')
        ->GetQueueGroupID( QueueID => $Param{ QueueID } );

    if ( !$GroupID ) {
        $Result = {
            Response => "ERROR",
            Message  => "Queue is incorrect"
        };
        return $Result;
    }
    elsif ( !$Param{ CustomerCreateTicket } ) {
        my $Group = $Kernel::OM->Get('Kernel::System::Group')->GroupLookup(
            GroupID => $GroupID,
        );

        my $CanCreateTicket = $Kernel::OM->Get('Kernel::System::Group')->PermissionCheck(
            UserID    => $Param{UserID},
            GroupName => $Group,
            Type      => 'create'
        );

        if ( !$CanCreateTicket ) {
            $Result = {
                Response => "ERROR",
                Message  => "No permission"
            };
            return $Result;
        }
    }

    # По выбору
    # ArticleType SenderType OwnerID Lock To Cc ReplyTo ContentType CustomerID
    # CustomerUser StateID

    my $DefaultState = $Kernel::OM->Get('Kernel::Config')
                       ->Get('RS::API::DefaultState') || 'new';

    #Alder
    
    if ( $Param{CustomerCreateTicket} ) {
        $Param{CustomerID} = $Param{UserCustomerID};
        $Param{CustomerUserID} = $Param{UserID};
        $Param{UserID} = "1";
    }                     

    my $OwnerID = $Param{OwnerID} || $Param{UserID};

    my $Lock = $Param{Lock};
    if ( !$Lock ) {
        $Lock = $Param{OwnerID} ? 'lock' : 'unlock';
    }

    my $TicketID = $TicketObject->TicketCreate(
        Title        => $Param{Title},
        QueueID      => $Param{QueueID},
        Lock         => $Lock,

        ( $Param{TypeID} ?
            ( TypeID => $Param{TypeID} ) : () ),
        ( $Param{ServiceID} ?
            ( ServiceID => $Param{ServiceID} ) : () ),
        ( $Param{SLAID} ?
            ( SLAID => $Param{SLAID} ) : () ),

        ( $Param{StateID} ?
            ( StateID => $Param{StateID} ) : ( State => $DefaultState ) ),
        PriorityID   => $Param{PriorityID},
        ( $Param{CustomerID} ?
            ( CustomerID => $Param{CustomerID} ) : () ),

        ( $Param{CustomerUserID} ?
            ( CustomerUser => $Param{CustomerUserID} ) : () ),

        OwnerID      => $OwnerID || "1",
        UserID       => $Param{UserID}
    );

    if ( !$TicketID ) {

        $Result = {
            Response => "ERROR",
            Message  => "Couldn't create ticket"
        };

    } else {
        my %User = $Kernel::OM->Get('Kernel::System::User')->GetUserData(
            UserID => $Param{UserID}
        );

        # Если указан клиент, то используем его
        my $From = '';
        if ( $Param{ CustomerUserID } ) {
            my %CustomerUser = $Kernel::OM->Get('Kernel::System::CustomerUser')->CustomerUserDataGet(
                User => $Param{ CustomerUserID }
            );

            my $UserFirstname = $CustomerUser{ UserFirstname } // '';
            my $UserLastname  = $CustomerUser{ UserLastname }  // '';

            $From = "$UserFirstname $UserLastname";
            $From =~ s/^\s+//;
            $From =~ s/\s+$//;

            if ( $From ) {
                $From = '"'.$From.'"';

                if ( $CustomerUser{ UserEmail } ) {
                    $From .= ' <'. $CustomerUser{ UserEmail } .'>';
                }
            }
        } else {
            $From = $User{UserFullname};
        }

        my $ArticleObject        = $Kernel::OM->Get('Kernel::System::Ticket::Article');
        my $ArticleBackendObject = $ArticleObject->BackendForChannel(
            ChannelName => ucfirst($Param{ArticleType} || 'Phone')# phone, email, chat, internal
        );

        my $ArticleID = $ArticleBackendObject->ArticleCreate(
            TicketID       => $TicketID,

            SenderType     => $Param{SenderType}
                              || 'customer', # agent|system|customer

            IsVisibleForCustomer => 1,

            # 'Some Agent <email@example.com>'
            From => $From,

            ( $Param{To} ?
                ( To => $Param{To} ) : () ),

            ( $Param{Cc} ?
                ( Cc => $Param{Cc} ) : () ),

            ( $Param{ReplyTo} ?
                ( ReplyTo => $Param{ReplyTo} ) : () ),

            Subject        => $Param{Title},
            Body           => $Param{Body},
            ContentType    => $Param{ContentType}
                              || 'text/plain; charset=utf-8', # or optional Charset & MimeType
            HistoryType    => 'AddNote', # EmailCustomer|Move|AddNote|PriorityUpdate|WebRequestCustomer|...
            HistoryComment => 'Ticket created!',
            UserID         => $Param{UserID}
        );

        if ( $ArticleID ) {
            my @FailedOperations = ();

            if ( $Param{Estimated} ) {

                $Param{Estimated} =~ s/[^0-9.]//g;

                my $Success = $TicketObject->TicketAccountTime(
                    TicketID  => $TicketID,
                    ArticleID => $ArticleID,
                    TimeUnit  => $Param{Estimated},
                    UserID    => $Param{UserID}
                );

                if ( !$Success ) {
                    push @FailedOperations, 'SetEstimatedTime';
                }
            }

            my $DateTimeObject;
            if ( $Param{UntilTimeDateUnix} ) {
                $DateTimeObject = $Kernel::OM->Create(
                    'Kernel::System::DateTime',
                    ObjectParams => {
                        Epoch => $Param{ UntilTimeDateUnix }
                    }
                );
            }
            elsif ( $Param{Year} ) {
                $DateTimeObject = $Kernel::OM->Create(
                    'Kernel::System::DateTime',
                    ObjectParams => {
                        Year     => $Param{Year},
                        Month    => $Param{Month},
                        Day      => $Param{Day},
                        Hour     => $Param{Hour},
                        Minute   => $Param{Minute},
                        TimeZone => $User{UserTimeZone}
                    }
                );
            }

            if ( $DateTimeObject ) {
                $DateTimeObject->ToOTRSTimeZone();

                my $Success = $TicketObject->TicketPendingTimeSet(
                    String   => $DateTimeObject->ToString,
                    TicketID => $TicketID,
                    UserID   => $Param{UserID}
                );

                if ( !$Success ) {
                    push @FailedOperations, 'PendingTime';
                }
            }

            if ( $Param{DynamicFields} ) {

                for my $DynamicFieldName ( sort keys %{ $Param{DynamicFields} } ) {
                    my $Success = $Self->SetDynamicFieldValue(
                        Name     => $DynamicFieldName,
                        Value    => $Param{DynamicFields}{$DynamicFieldName},
                        TicketID => $TicketID
                    );

                    push @FailedOperations, 'DynamicField_'.$DynamicFieldName if !$Success;
                }
            }

            if ( @FailedOperations ) {

                $Result = {
                    Response  => "ERROR",
                    Message   => 'Ticket was created but these operations are failed: '.
                                 join(', ', @FailedOperations ),
                    TicketID => $TicketID
                };

            } else {

                $Result = {
                    Response => "OK",
                    TicketID => $TicketID
                };
            }

        } else {

            $Result = {
                Response => "ERROR",
                Message  => "Cannot add ticket article"
            };
        }
    }

    return $Result;
}

sub CreateArticle {
    my ( $Self, %Param ) = @_;

    my $Result;
    my $TicketObject = $Self->{TicketObject};

    my @FailedRequiredParams = ();

    # Required
    for ( qw/ TicketID Subject Body / ) {
        if ( !$Param{$_} ) {
            push @FailedRequiredParams, $_;
        }
    }

    if ( @FailedRequiredParams ) {
        return {
            Response => "ERROR",
            Message  => "Required fields is not defined: "
                        .join(", ", @FailedRequiredParams )
        };
    }

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    my $HasPermission = $Self->_CheckGroupPermission(
        QueueID => $Ticket{QueueID},
        Type    => ['note', 'owner'],
        UserID  => $Param{UserID}
    );

    if ( !$HasPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    # По выбору
    # ArticleType SenderType From To Cc ReplyTo ContentType

    my %User = $Kernel::OM->Get('Kernel::System::User')->GetUserData(
        UserID => $Param{UserID}
    );

    $Param{ArticleType} //= '';

    my $ArticleType = 'Internal';
    my $IsVisibleForCustomer = $Param{ArticleType} =~ /external/i;
    if ( $Param{ArticleType} =~ /^chat/i ) {
        $ArticleType = 'Chat';

    } elsif ( $Param{ArticleType} =~ /^phone/i ) {
        $ArticleType = 'Phone';

    } elsif ( $Param{ArticleType} =~ /^email/i ) {
        $ArticleType = 'Email';
    }

    my $ArticleObject        = $Kernel::OM->Get('Kernel::System::Ticket::Article');
    my $ArticleBackendObject = $ArticleObject->BackendForChannel(
        ChannelName => $ArticleType # phone, email, chat, internal
    );

    my %ArticleParam = (
        %Param,
        TicketID       => $Param{TicketID},
        IsVisibleForCustomer => $IsVisibleForCustomer,
#            ArticleType    => $Param{ArticleType}
#                              || 'phone', # email-external|email-internal|phone|fax|...

        SenderType     => $Param{SenderType} || 'agent',  # agent|system|customer

        # 'Some Agent <email@example.com>'
        From => $User{UserFullname}.' '.'<'.$User{UserEmail}.'>',

        ( $Param{To} ?
            ( To => $Param{To} ) : () ),

        ( $Param{Cc} ?
            ( Cc => $Param{Cc} ) : () ),

        ( $Param{ReplyTo} ?
            ( ReplyTo => $Param{ReplyTo} ) : () ),

        Subject        => $Param{Subject},
        Body           => $Param{Body},
        ContentType    => $Param{ContentType}
                          || 'text/plain; charset=utf-8', # or optional Charset & MimeType
        Charset        => $Param{Charset}  || 'utf-8',
        MimeType       => $Param{MimeType} || 'text/plain',
        HistoryType    => 'AddNote', # EmailCustomer|Move|AddNote|PriorityUpdate|WebRequestCustomer|...
        HistoryComment => '%%Note',

        UserID         => $Param{UserID}
    );

    my $ArticleID;

    if ( $ArticleType eq 'Email' ) {
        my $TemplateGenerator = $Kernel::OM->Get('Kernel::System::TemplateGenerator');
        my %Data = $Kernel::OM->Get('Kernel::System::TemplateGenerator')->Attributes(
            TicketID => $Param{TicketID},
            Data     => {},
            UserID   => $Param{UserID}
        );

        $ArticleID = $ArticleBackendObject->ArticleSend( %ArticleParam, From => $Data{From} );
    }
    else {
        $ArticleID = $ArticleBackendObject->ArticleCreate( %ArticleParam );
    }

    if ( $ArticleID ) {
        my @FailedOperations = ();

        if ( $Param{Estimated} ) {

            $Param{Estimated} =~ s/[^0-9.]//g;

            my $Success = $TicketObject->TicketAccountTime(
                TicketID  => $Param{TicketID},
                ArticleID => $ArticleID,
                TimeUnit  => $Param{Estimated},
                UserID    => $Param{UserID}
            );

            if ( !$Success ) {
                push @FailedOperations, 'SetEstimatedTime';
            }
        }

        if ( $Param{State} or $Param{StateID} ) {

            my $Success = $TicketObject->TicketStateSet(
                State    => $Param{State},
                StateID  => $Param{StateID},
                TicketID => $Param{TicketID},
                UserID   => $Param{UserID}
            );

            if ( !$Success ) {
                push @FailedOperations, 'UpdateState';
            }
        }

        my $DateTimeObject;
        if ( $Param{UntilTimeDateUnix} ) {
            $DateTimeObject = $Kernel::OM->Create(
                'Kernel::System::DateTime',
                ObjectParams => {
                    Epoch => $Param{ UntilTimeDateUnix }
                }
            );
        }
        elsif ( $Param{Year} ) {
            $DateTimeObject = $Kernel::OM->Create(
                'Kernel::System::DateTime',
                ObjectParams => {
                    Year     => $Param{Year},
                    Month    => $Param{Month},
                    Day      => $Param{Day},
                    Hour     => $Param{Hour},
                    Minute   => $Param{Minute},
                    TimeZone => $User{UserTimeZone}
                }
            );
        }

        if ( $DateTimeObject ) {
            $DateTimeObject->ToOTRSTimeZone();

            my $Success = $TicketObject->TicketPendingTimeSet(
                String   => $DateTimeObject->ToString,
                TicketID => $Param{TicketID},
                UserID   => $Param{UserID}
            );

            if ( !$Success ) {
                push @FailedOperations, 'PendingTime';
            }
        }

        if ( $Param{DynamicFields} ) {

            for my $DynamicFieldName ( sort keys %{ $Param{DynamicFields} } ) {
                my $Success = $Self->SetDynamicFieldValue(
                    Name     => $DynamicFieldName,
                    Value    => $Param{DynamicFields}{$DynamicFieldName},
                    TicketID => $Param{TicketID}
                );

                push @FailedOperations, 'DynamicField_'.$DynamicFieldName if !$Success;
            }
        }

        if ( @FailedOperations ) {

            $Result = {
                Response  => "ERROR",
                Message   => 'Article was created but these operations are failed: '.
                             join(', ', @FailedOperations ),
                ArticleID => $ArticleID
            };

        } else {

            $Result = {
                Response  => "OK",
                ArticleID => $ArticleID
            };
        }

    } else {

        $Result = {
            Response => "ERROR",
            Message  => "Cannot add article"
        };
    }

    return $Result;
}

sub GetTicketList {
    my ( $Self, %Param ) = @_;

    my $DynamicFieldsMode = $Param{DynamicFieldsMode} // 'none';

    my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');

    my $Result;
    my $TicketObject = $Self->{TicketObject};

    if ( $Param{CustomerGetTicketList} ) {
        $Param{CustomerID} = $Param{UserCustomerID};
        $Param{CustomerUserID} = $Param{UserID};
        $Param{UserID} = "1";
    }       

    my $UserToken = $Self->{UtilObject}->GetUserToken( UserID => $Param{UserID} );
    my $NeedTokenUpdate = $UserToken ? 0 : 1;

    my $SmartSort = $Param{SmartSort} || 0;
    my $ResultType = $Param{Count} ? 'COUNT' : 'ARRAY';

    my $TicketRequestParams = $Self->_GetTicketRequestParams(
        %Param,
        ResultType => $ResultType,
        UserID     => $Param{UserID}
    );

    my $ViewParams  = $TicketRequestParams->{ ViewParams };
    my %TicketParam = %{ $TicketRequestParams->{ TicketParam } };

    # Определяем существует ли доступная пользователю заявка с предполагаемым
    # TicketNumber в виде числа из FullTextSearch
    # ---
    my $TicketIDIndirect = 0;
    my $TicketIndirect;
    if ( $TicketParam{ TicketNumberFromFullTextSearch } ) {
        my $TicketID = $TicketObject->TicketCheckNumber(
            Tn => $TicketParam{ TicketNumberFromFullTextSearch }
        );

        if ( $TicketID ) {
            my %Ticket = $TicketObject->TicketGet(
                TicketID => $TicketID,
                UserID   => $Param{UserID}
            );

            if ( %Ticket ) {
                $TicketIndirect = $Self->_ClearObjectFields(
                    Object => \%Ticket,
                    Type   => 'Ticket'
                );

                $TicketIDIndirect = $TicketID;
            }
        }
    }
    # ---

    if ( $ResultType eq 'COUNT') {

        my $Count = 0;

        # ->TicketSearch: Permission RO (RW) by default
        #my @TicketIDs = ();

        my $FoundCount = 0;
        if ( @{ $ViewParams } ) {

            for ( @{ $ViewParams } ) {
                $FoundCount = $TicketObject->TicketSearch( %$_, %TicketParam );
                $Count += $FoundCount;
            }

        } else {
            $FoundCount = $TicketObject->TicketSearch( %TicketParam );
            $Count += $FoundCount;
        }

        # Учитываем найденную заявку по TicketNumber из FullTextSearch вместе с
        # остальными, которые выдал TicketSearch
        # ---
        # TODO:
=pod
        my $AlreadyFound = 0;
        for my $TicketID ( @TicketIDs ) {
            if ( $TicketID = $TicketIDIndirect ) {
                $AlreadyFound = 1;
            }
        }

        if ( !$AlreadyFound and $TicketIDIndirect ) {
            $Count++;
        }
=cut
        # ---

        $Result = {
            Response        => 'OK',
            Count           => $Count,
            NeedTokenUpdate => $NeedTokenUpdate
        };

    } else {

        my @TicketList = ();
        my @TicketIDs  = ();

        if ( @{$ViewParams} ) {

            for ( @{$ViewParams} ) {

                if ($SmartSort) {
                    @TicketIDs = $Self->_SmartTicketSearch( %$_, %TicketParam );
                }
                else {
                    my @PartTicketIDs =
                      $TicketObject->TicketSearch( %$_, %TicketParam );
                    push @TicketIDs, @PartTicketIDs;
                }
            }

        }
        else {
            if ($SmartSort) {
                @TicketIDs = $Self->_SmartTicketSearch( %TicketParam );
            }
            else {
                @TicketIDs = $TicketObject->TicketSearch(%TicketParam);
            }
        }
        my $Count += @TicketIDs;
        $Param{Offset} //= 0;
        @TicketIDs = splice( @TicketIDs, $Param{Offset}, $Param{Limit} // 5 );

        my %User = $Kernel::OM->Get('Kernel::System::User')->GetUserData(
            UserID => $Param{UserID}
        );

        my $LanguageObject = Kernel::Language->new(
            UserLanguage => 'pt', # pt - просто потому что там нужный DateFormat Y-M-D H:M:S
            UserTimeZone => $User{UserTimeZone}
        );

        my $i = 0;

        while ( $i < @TicketIDs ) {
            my $ShowDynamicFields =
                ( $DynamicFieldsMode eq 'all' or
                  $DynamicFieldsMode eq 'mobile' ) ? 1 : 0;

            my %Ticket = $TicketObject->TicketGet(
                TicketID => $TicketIDs[$i],
                UserID   => $Param{UserID},
                ( $ShowDynamicFields ? ( DynamicFields => 1 ) : () )
            );

            my $DynamicFields = {};
            if ( $ShowDynamicFields ) {

                my $List = $Kernel::OM->Get('Kernel::System::DynamicField')
                           ->DynamicFieldListGet();

                my %Result = ();
                for my $Field ( @{$List} ) {

                    $DynamicFields->{ $Field->{Name} } = {
                        ID         => $Field->{ID},
                        Name       => $Field->{Name},
                        Label      => $Field->{Label},
                        FieldType  => $Field->{FieldType},
                        ObjectType => $Field->{ObjectType},
                        Config     => {
                            (
                                $Field->{Config}{PossibleValues}
                                ? ( PossibleValues => $Field->{Config}{PossibleValues} )
                                : ()
                            )
                        }
                    };
                }
            }

            my $ScreenDynamicFields = $Kernel::OM->Get('Kernel::Config')
                             ->Get("RS:API::Ticket::MobileScreen::DynamicFields");
            my $DynamicFieldSet = {};
            my $AllDynamicFields = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
                ObjectType => 'Ticket'
            );

            # Transform the date values from the ticket data (but not the dynamic field values).
            ATTRIBUTE:
            for my $Attribute ( sort keys %Ticket ) {
                if ( $Attribute =~ m{ \A DynamicField_(\w+) }xms ) {
                    my $TicketDFValue = delete $Ticket{$Attribute};

                    next ATTRIBUTE if $DynamicFieldsMode eq 'none';

                    my $DynamicFieldName = $1;
                    my $DynamicFieldType;
                    for my $DynamicField ( @{$AllDynamicFields} ) {
                        if ( $DynamicField->{Name} eq $DynamicFieldName ) {
                            $DynamicFieldType = $DynamicField->{FieldType};
                        }
                    }

                    if ( $DynamicFieldsMode eq 'mobile' ) {
                        for my $Screen ( sort keys %{$ScreenDynamicFields} ) {
                            next
                              if not exists $ScreenDynamicFields->{$Screen}
                              {$DynamicFieldName};

                            if ( exists $DynamicFieldSet->{$DynamicFieldName} )
                            {
                                $DynamicFieldSet->{$DynamicFieldName}{Screens}
                                  {$Screen} = $ScreenDynamicFields->{$Screen}
                                  {$DynamicFieldName};
                            }
                            else {
                                $DynamicFieldSet->{$DynamicFieldName}{Name} =
                                  $DynamicFieldName;
                                $DynamicFieldSet->{$DynamicFieldName}{Type} =
                                  $DynamicFieldType;

                                if ( $DynamicFieldType eq 'Dropdown' ) {
                                    $DynamicFieldSet->{$DynamicFieldName}{Value} =
                                        $DynamicFields->{ $DynamicFieldName }
                                          { Config }
                                          { PossibleValues }
                                          { $TicketDFValue };
                                }
                                else {
                                    $DynamicFieldSet->{$DynamicFieldName}{Value} =
                                      $TicketDFValue;
                                }

                                $DynamicFieldSet->{$DynamicFieldName}{Screens}
                                  {$Screen} = $ScreenDynamicFields->{$Screen}
                                  {$DynamicFieldName};
                            }
                        }
                    }
                    elsif ( $DynamicFieldsMode eq 'all' ) {
                        for my $Screen ( sort keys %{$ScreenDynamicFields} ) {
                            if ( exists $DynamicFieldSet->{$DynamicFieldName} )
                            {
                                if (
                                    exists $ScreenDynamicFields->{$Screen}
                                    {$DynamicFieldName} )
                                {
                                    $DynamicFieldSet->{$DynamicFieldName}
                                      {Screens}{$Screen} =
                                      $ScreenDynamicFields->{$Screen}
                                      {$DynamicFieldName};
                                }
                            }
                            else {
                                $DynamicFieldSet->{$DynamicFieldName}{Name} =
                                  $DynamicFieldName;
                                $DynamicFieldSet->{$DynamicFieldName}{Type} =
                                  $DynamicFieldType;

                                if ( $DynamicFieldType eq 'Dropdown' ) {
                                    $DynamicFieldSet->{$DynamicFieldName}{Value} =
                                        $DynamicFields->{ $DynamicFieldName }
                                          { Config }
                                          { PossibleValues }
                                          { $TicketDFValue };
                                }
                                else {
                                    $DynamicFieldSet->{$DynamicFieldName}{Value} =
                                      $TicketDFValue;
                                }

                                if (
                                    exists $ScreenDynamicFields->{$Screen}
                                    {$DynamicFieldName} )
                                {
                                    $DynamicFieldSet->{$DynamicFieldName}
                                      {Screens}{$Screen} =
                                      $ScreenDynamicFields->{$Screen}
                                      {$DynamicFieldName};
                                }
                            }
                        }
                    }

                    next ATTRIBUTE;
                }

                next ATTRIBUTE if !$Ticket{$Attribute};

                if ( $Ticket{$Attribute} =~ m{\A(\d\d\d\d)-(\d\d)-(\d\d)\s(\d\d):(\d\d):(\d\d)\z}xi ) {
                    my $OriginValue = $Ticket{$Attribute};
                    $Ticket{$Attribute."Server"} = $Ticket{$Attribute};

                    $Ticket{$Attribute} = $LanguageObject->FormatTimeString(
                        $OriginValue,
                        'DateFormat',
                        0,
                        1 # не добавляем (TZ) в преобразованную дату
                    );
                }
            }

            $Ticket{DynamicFields} = $DynamicFieldSet;

            $Ticket{ServiceID} ||= undef;
            $Ticket{SLAID}     ||= undef;

            # Наблюдатели
            my @Watchers = $TicketObject->TicketWatchGet(
                TicketID => $Ticket{ TicketID },
                Result   => 'ARRAY'
            );

            $Ticket{ WatcherCount } = @Watchers;
            $Ticket{ HasWatch } = 0;

            for (@Watchers) {
                if ( $Param{UserID} == $_ ) {
                    $Ticket{ HasWatch } = 1;
                    last;
                }
            }

            my %Flags = $TicketObject->TicketFlagGet(
                TicketID => $TicketIDs[$i],
                UserID   => $Param{UserID}
            );

            if ( $Flags{ Seen } ) {
                $Ticket{Seen} = 1;
            } else {
                $Ticket{Seen} = 0;
            }

            my %CustomerUser = $Kernel::OM->Get('Kernel::System::CustomerUser')->CustomerUserDataGet(
                User => $Ticket{ CustomerUserID }
            );

            $Ticket{ CustomerUserFirstname } = $CustomerUser{ UserFirstname };
            $Ticket{ CustomerUserLastname }  = $CustomerUser{ UserLastname };

            # Количество статей при подробном просмотре
            if ( $TicketParam{TicketID} ) {
                $ArticleObject->_ArticleCacheClear(
                    TicketID => $TicketParam{TicketID}
                );

                my @AllArticles = $ArticleObject->ArticleList(
                    TicketID => $TicketParam{TicketID}
                );

                $Ticket{ ArticleCount } = @AllArticles;

                $Ticket{ ConsumedTime } = $TicketObject->TicketAccountedTimeGet(
                    TicketID => $TicketParam{TicketID}
                );

                my $Links= $Kernel::OM->Get('Kernel::System::LinkObject')->LinkListWithData(
                    Object   => 'Ticket',
                    Key      => $TicketParam{ TicketID },
                    Object2   => 'Ticket',
                    State     => 'Valid',
                    UserID    => 1,
                );

                my %TypeList = $Kernel::OM->Get('Kernel::System::LinkObject')->TypeList(
                    UserID => $Param{UserID}
                );

                my @Links = ();
                for my $LinkType ( keys %{ $Links->{Ticket} } ) {
                    for my $LinkDest (qw/Source Target/) {
                        for my $TicketID ( keys %{ $Links->{Ticket}{ $LinkType }{ $LinkDest } } ) {
                            my $Ticket = $Links->{Ticket}{ $LinkType }{ $LinkDest }{ $TicketID };
                            push @Links, {
                                TicketID     => $TicketID,
                                TicketNumber => $Ticket->{TicketNumber},
                                Title      => $Ticket->{Title},
                                PriorityID => $Ticket->{PriorityID},
                                TypeID     => $Ticket->{TypeID},
                                LinkType   => $LinkType,
                                LinkDest   => $LinkDest,

                                LinkTypeTitle => $TypeList{ $LinkType }{ $LinkDest.'Name' }
                            }
                        }
                    }
                }
                $Ticket{ Links } = \@Links;
                $Ticket{ LinkCount } = scalar @Links;

                # Вложения
                my $FirstArticleID = $AllArticles[0]{ ArticleID };
                my $ArticleBackendObject = $ArticleObject->BackendForArticle(
                    TicketID  => $TicketParam{TicketID},
                    ArticleID => $FirstArticleID
                );

                my %Attachments = $ArticleBackendObject->ArticleAttachmentIndex(
                    ArticleID => $FirstArticleID,
                );

                my @Atts = ();
                my $HTMLBody;
                for my $FileID ( keys %Attachments ) {
                    for my $Field ( keys %{ $Attachments{$FileID} } ) {
                        if ( defined $Attachments{$FileID}->{$Field}
                            and $Attachments{$FileID}->{$Field} eq '' )
                        {
                            $Attachments{$FileID}->{$Field} = undef;
                        }
                    }

                    if ( $Attachments{$FileID}->{Disposition} eq 'attachment' )
                    {
                        push @Atts,
                          { FileID => $FileID, %{ $Attachments{$FileID} } };
                    }
                    else {
                        $HTMLBody = $Attachments{$FileID};

                        $HTMLBody->{FileID} = $FileID;
                    }
                }

                $Ticket{ Attachments } = \@Atts;
                $Ticket{HTMLBody}      = $HTMLBody;

                # ----------------------------------------------------------------
                my @AttachmentAll = ();
                for my $Article ( @AllArticles ) {
                    my $ArticleID = $Article->{ArticleID};

                    my %Attachments = $ArticleBackendObject->ArticleAttachmentIndex(
                        ArticleID => $ArticleID
                    );

                    for my $FileID ( keys %Attachments ) {
                        for my $Field ( keys %{ $Attachments{$FileID} } ) {
                            if ( defined $Attachments{$FileID}->{$Field}
                                and $Attachments{$FileID}->{$Field} eq '' )
                            {
                                $Attachments{$FileID}->{$Field} = undef;
                            }
                        }

                        if ( $Attachments{$FileID}->{Disposition} eq
                            'attachment' )
                        {
                            push @AttachmentAll,
                              {
                                FileID => $FileID,
                                %{ $Attachments{$FileID} },
                                ArticleID => $ArticleID
                              };
                        }
                    }

                }

                $Ticket{ AttachmentAll } = \@AttachmentAll;
                # ----------------------------------------------------------------

                # Наблюдатели
                my @Watchers = $TicketObject->TicketWatchGet(
                    TicketID => $TicketParam{ TicketID },
                    Result   => 'ARRAY'
                );

                $Ticket{ Watchers } = [];

                for my $WatcherUserID ( @Watchers ) {
                    my %User = $Kernel::OM->Get('Kernel::System::User')->GetUserData(
                        UserID => $WatcherUserID
                    );

                    push @{ $Ticket{ Watchers } }, {
                        FirstName => $User{ UserFirstname },
                        LastName  => $User{ UserLastname },
                        UserID    => $WatcherUserID,
                        Login     => $User{ UserLogin }
                    };
                }


                if ( $Ticket{ OwnerID } ) {
                    my %User = $Kernel::OM->Get('Kernel::System::User')->GetUserData(
                        UserID => $Ticket{ OwnerID }
                    );

                    $Ticket{OwnerFirstname} = $User{ UserFirstname };
                    $Ticket{OwnerLastname}  = $User{ UserLastname };
                }
            }

            if ( !exists $Ticket{ LinkCount } ) {
                my %LinkKeyList = $Kernel::OM->Get('Kernel::System::LinkObject')->LinkKeyList(
                    Object1   => 'Ticket',
                    Key1      => $TicketIDs[$i],
                    Object2   => 'Ticket',
                    State     => 'Valid',
                    UserID    => 1,
                );

                $Ticket{ LinkCount } = scalar keys %LinkKeyList;
            }

            $Ticket{ UntilTimeDate }     = 0;
            $Ticket{ UntilTimeDateUnix } = 0;

            if ( $Ticket{ UntilTime } ) {
                $Ticket{ UntilTimeDateUnix } = $Ticket{ UntilTime } + time;

                my $DateTimeObject = $Kernel::OM->Create(
                    'Kernel::System::DateTime',
                    ObjectParams => {
                        Epoch => $Ticket{ UntilTimeDateUnix }
                    }
                );

                my $Success = $DateTimeObject->ToTimeZone(
                    TimeZone => $User{UserTimeZone}
                );

                if ( $Success ) {
                    $Ticket{ UntilTimeDate } = $DateTimeObject->ToString;
                }
                else {
                    $Kernel::OM->Get('Kernel::System::Log')->Log(
                        Priority => 'error',
                        Message  => "Cannot convert " . $Ticket{ UntilTimeDateUnix }
                          . " to UserTimeZone ('$User{UserTimeZone}') value"
                    );
                }
            }

            $Ticket{ CreateTimeUnix } = str2time( $Ticket{CreatedServer}. '+0000' );

            # Take into account type of fields when they are empty
            # TODO: removed everything not for ticket
            my $Ticket = $Self->_ClearObjectFields(
                Object => \%Ticket,
                Type   => 'Ticket'
            );

            push @TicketList, $Ticket;

            $i++
        }

        $Result = {
            Response => 'OK',
            Count    => $Count,
            Tickets  => \@TicketList,
            (
                $TicketIDIndirect
                ? (
                    TicketIDFromFullTextSearch => $TicketIDIndirect,
                    TicketFromFullTextSearch   => $TicketIndirect
                  )
                : ()
            ),
            NeedTokenUpdate => $NeedTokenUpdate
        };
    }

    return $Result;
}

sub UpdateLock {
    my ( $Self, %Param ) = @_;

    my $Result;
    my $TicketObject = $Self->{TicketObject};

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    if ( $Ticket{OwnerID} != $Param{UserID} ) {
        my $HasPermission = $Self->_CheckGroupPermission(
            QueueID => $Ticket{QueueID},
            UserID  => $Param{UserID}
        );

        if ( !$HasPermission ) {
            return {
                Response => 'ERROR',
                Message  => 'No permission'
            };
        }
    }

    my $Success = $TicketObject->TicketLockSet(
        Lock     => $Param{Lock},
        LockID   => $Param{LockID},
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( $Success ) {

        if ( $TicketObject->TicketLockGet(
                TicketID => $Param{TicketID}
             ) ) {

            my $Success = $TicketObject->TicketOwnerSet(
                NewUserID => $Param{UserID},
                TicketID  => $Param{TicketID},
                UserID    => $Param{UserID}
            );

            if ( $Success ) {
                $Result = { Response => "OK" };
            } else {
                $Result = {
                    Response => "ERROR",
                    Message  => "Ticket was locked but Owner couldn't be changed",
                };
            }

        } else {
            $Result = { Response => "OK" };
        }

    } else {
        $Result = {
            Response => "ERROR",
            Message  => "Couldn't update lock state",
        };
    }

    return $Result;
}

sub MarkTicketAsSeen {
    my ( $Self, %Param ) = @_;

    my $Result;

    my $TicketObject = $Self->{TicketObject};

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    my $HasPermission = $Self->_CheckGroupPermission(
        QueueID => $Ticket{QueueID},
        Type    => ['ro'],
        UserID  => $Param{UserID}
    );

    if ( !$HasPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    my $Success = $TicketObject->TicketFlagSet(
        Key      => 'Seen',
        Value    => $Param{Seen},
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( $Success ) {

        $Result = {
            Response => "OK"
        };

    } else {

        $Result = {
            Response => "ERROR",
            Message  => "Couldn't mark ticket as seen",
        };
    }

    return $Result;
}

sub MarkArticleAsSeen {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Self->{TicketObject};

    my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    # TODO: check TicketGet permissions check with this one
    my $HasPermission = $Self->_CheckGroupPermission(
        QueueID => $Ticket{QueueID},
        Type    => ['ro'],
        UserID  => $Param{UserID}
    );

    if ( !$HasPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    # TODO: переделать
    my $ArticleRow = $Kernel::OM->Get('Kernel::System::DB')->SelectAll(
        SQL => q{
            SELECT ticket_id FROM article WHERE id = ?
        },
        Bind => [ \$Param{ArticleID} ]
    ) // [];

    my $TicketID = $Param{TicketID} || 0;

    if ( !$TicketID and @{ $ArticleRow } ) {
        $TicketID = $ArticleRow->[0][0];
    }

    my $Result;
    if ( !$TicketID ) {
        $Result = {
            Response => "ERROR",
            Message  => "No TicketID"
        };
    }

    my $Success;

    if ( $TicketID ) {
        $Success = $ArticleObject->ArticleFlagSet(
            Key       => 'Seen',
            Value     => $Param{Seen},
            TicketID  => $TicketID,
            ArticleID => $Param{ArticleID},
            UserID    => $Param{UserID}
        );
    }

    if ( $Success ) {

        my $ArticleBackendObject = $ArticleObject->BackendForArticle(
            TicketID  => $TicketID,
            ArticleID => $Param{ArticleID},
        );

        my %Article = $ArticleBackendObject->ArticleGet(
            TicketID  => $TicketID,
            ArticleID     => $Param{ArticleID},
            DynamicFields => 0,
            UserID        => $Param{UserID}
        );

        my %Ticket = $TicketObject->TicketGet(
            TicketID => $Article{TicketID},
            UserID   => $Param{UserID}
        );

        $Kernel::OM->Get('Kernel::System::Cache')->Delete(
            Type => 'Ticket',
            Key  => 'TicketFlag::'.$Article{TicketID}
        );

        my %Flags = $TicketObject->TicketFlagGet(
            TicketID => $Article{TicketID},
            UserID   => $Param{UserID}
        );

        if ( $Flags{ Seen } ) {
            $Ticket{Seen} = 1;
        } else {
            $Ticket{Seen} = 0;
        }

        $Result = {
            Response   => "OK",
            TicketID   => $TicketID,
            TicketSeen => $Ticket{Seen}
        };

    } else {

        $Result = {
            Response => "ERROR",
            Message  => "Couldn't mark article as seen",
        };
    }

    return $Result;
}

sub UpdateTicket {
    my ( $Self, %Param ) = @_;

    my $Result;

    my %Ticket = $Self->{TicketObject}->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID},
        Silent   => 1
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    my @FieldsForUpdate = qw/
      Title
      Queue
      QueueID
      Type
      TypeID
      Service
      ServiceID
      SLA
      SLAID
      CustomerID
      CustomerUserID
      Lock
      LockID
      ArchiveFlag
      State
      StateID
      NewOwner
      NewOwnerID
      NewResponsibleUser
      NewResponsibleUserID
      Priority
      PriorityID
      UntilTimeDateUnix
      Year
      Month
      Day
      Hour
      Minute
      DynamicFields
      /;

    my $HasParamForUpdate = 0;
    for my $FieldName ( @FieldsForUpdate ) {
        if ( exists $Param{ $FieldName } and $Param{ $FieldName } ) {
            $HasParamForUpdate = 1;
            last;
        }
    }

    if ( !$HasParamForUpdate ) {
        return {
            Response => 'ERROR',
            Message  => 'Pass some fields for ticket update: '
              . join( ', ', @FieldsForUpdate )
        };
    }

    my @FailedUpdatedItems = $Self->_UpdateTicket(
        %Param,
        Ticket => \%Ticket
    );

    if ( @FailedUpdatedItems ) {

        $Result = {
            Response => "ERROR",
            Message  => "The follow parameters wasn't updated: ".
                         join(', ', @FailedUpdatedItems )
        };

    } else {
        $Result = { Response => "OK" };
    }

    return $Result;
}

sub GetArticles {
    my ( $Self, %Param ) = @_;

    my $TicketObject  = $Self->{TicketObject};
    my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID},
        Silent   => 1
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    my $HasPermission = $Self->_CheckGroupPermission(
        QueueID => $Ticket{QueueID},
        Type    => ['ro'],
        UserID  => $Param{UserID}
    );

    if ( !$HasPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    if ( $Param{Count} ) {

        my @ArticleBoxAll = $ArticleObject->ArticleList(
            TicketID             => $Param{TicketID},
            IsVisibleForCustomer => $Param{IsVisibleForCustomer} // 1
        );

        return {
            Response => "OK",
            Count    => scalar @ArticleBoxAll
        };
    }

    my @CommunicationChannels = $Kernel::OM
        ->Get('Kernel::System::CommunicationChannel')->ChannelList();

    my %Channels = map { $_->{ChannelID} => $_->{ChannelName} } @CommunicationChannels;

    if ( !%Channels ) {
        return {
            Response => "OK",
            Articles => []
        };
    }

    my @MetaArticles = $ArticleObject->ArticleList(
        TicketID => $Param{TicketID},
    );

    $Param{Order} //= 'DESC';

    if ( $Param{Order} eq 'DESC' ) {
        @MetaArticles = reverse @MetaArticles;
    }

    my $Limit  = $Param{Limit} // 0;
    my $Offset;

    if ( $Limit and $Param{Page} and $Param{Page} > 1 ) {
        $Offset       = $Param{Page} * $Limit;
        @MetaArticles = splice( @MetaArticles, $Offset, $Limit );
    } elsif ( $Limit ) {
        @MetaArticles = splice( @MetaArticles, 0, $Limit );
    }

    my %User = $Kernel::OM->Get('Kernel::System::User')->GetUserData(
        UserID => $Param{UserID}
    );

    my $LanguageObject = Kernel::Language->new(
        UserLanguage => 'pt', # pt - просто потому что там нужный DateFormat Y-M-D H:M:S
        UserTimeZone => $User{UserTimeZone}
    );

    my @Articles = ();
    for my $MetaArticle ( @MetaArticles ) {
        my %Article = $ArticleObject
                      ->BackendForArticle( %{ $MetaArticle } )
                      ->ArticleGet(
                          %{ $MetaArticle },
                          DynamicFields => 1,
                          RealNames     => 1
                      );

        # Transform the date values from the ticket data (but not the dynamic field values).
        ATTRIBUTE:
        for my $Attribute ( sort keys %Article ) {
            next ATTRIBUTE if $Attribute =~ m{ \A DynamicField_ }xms;
            next ATTRIBUTE if !$Article{$Attribute};

            if ( $Article{$Attribute} =~ m{\A(\d\d\d\d)-(\d\d)-(\d\d)\s(\d\d):(\d\d):(\d\d)\z}xi ) {
                my $OriginValue = $Article{$Attribute};
                $Article{$Attribute."Server"} = $Article{$Attribute};

                $Article{$Attribute} = $LanguageObject->FormatTimeString(
                    $OriginValue,
                    'DateFormat',
                    0,
                    1 # не добавляем (TZ) в преобразованную дату
                );
            }
        }

        push @Articles, \%Article;
    }

    my %Flags = $ArticleObject->ArticleFlagsOfTicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    my %ArticleSenderTypeList = $ArticleObject->ArticleSenderTypeList();

    for my $Article ( @Articles ) {

        %{ $Article } = ( %{ $Article }, %Ticket );

        my $ArticleBackendObject = $ArticleObject->BackendForArticle( %{ $Article } );

        my $StripTicketNumberFromArticleSubject = $Kernel::OM->Get('Kernel::Config')
            ->Get("RS::API::StripTicketNumberFromArticleSubject") // '';

        if ( $StripTicketNumberFromArticleSubject ) {
            my $TicketHook = $Kernel::OM->Get('Kernel::Config')->Get("Ticket::Hook");

            # TODO: уточнить, почему его нет
            if ( $TicketHook ) {
                $Article->{Subject} =~ s/^\[$TicketHook\d+\]\s*//;
            }
        }

        $Article->{Avatar} = 'https://www.shareicon.net/data/128x128/2015/09/18/103160_man_512x512.png';

        my %Attachments = $ArticleBackendObject->ArticleAttachmentIndex(
            ArticleID => $Article->{ ArticleID },
        );

        my @Atts = ();
        my $HTMLBody;
        for my $FileID ( keys %Attachments ) {
            for my $Field ( keys %{ $Attachments{$FileID} } ) {
                if ( defined $Attachments{$FileID}->{$Field}
                    and $Attachments{$FileID}->{$Field} eq '' )
                {
                    $Attachments{$FileID}->{$Field} = undef;
                }
            }

            if ( $Attachments{$FileID}->{Disposition} eq 'attachment' ) {
                push @Atts, { FileID => $FileID, %{ $Attachments{$FileID} } };
            }
            else {
                $HTMLBody = $Attachments{$FileID};
                $HTMLBody->{FileID} = $FileID;
            }
        }

        $Article->{ Attachments } = \@Atts;
        $Article->{HTMLBody}      = $HTMLBody;

        if ( exists $Flags{ $Article->{ ArticleID } } and
                    $Flags{ $Article->{ ArticleID } }{ Seen } ) {
            $Article->{Seen} = 1;
        } else {
            $Article->{Seen} = 0;
        }

        $Article->{ Created } = $Article->{ CreateTime }; # !WARN для совместимости с otrs5
        # TODO: переименовать
        $Article->{ CreatedTimeUnix } = str2time( $Article->{ CreateTimeServer } .'+0000' );

        # ArticleType создаём вручную для "эмуляции" некоторых типов из otrs5
        # select name from article_type;
        # +------------------------+
        # | name                   |
        # +------------------------+
        # | email-external         |
        # | email-internal         |
        # | note-external          |
        # | note-internal          |
        # | phone                  |
        # +------------------------+
        my $ArticleType = '';
        my $ArticleChannel = $Channels{ $Article->{CommunicationChannelID} } // '';
        if ( $ArticleChannel eq 'Email' ) {
            $ArticleType = 'email';
            if ( $Article->{IsVisibleForCustomer} ) {
                $ArticleType .= '-external';
            } else {
                $ArticleType .= '-internal';
            }
        }
        elsif ( $ArticleChannel eq 'Phone' ) {
            $ArticleType = 'phone';
        }
        elsif ( $ArticleChannel eq 'Internal' ) {
            $ArticleType = 'note';
            if ( $Article->{IsVisibleForCustomer} ) {
                $ArticleType .= '-external';
            } else {
                $ArticleType .= '-internal';
            }
        }

        $Article->{ArticleType} = $ArticleType;

        if ( $ArticleChannel eq 'Internal' ) {
            $Article->{Direction} = 'Internal';
        }
        elsif ( $ArticleSenderTypeList{ $Article->{SenderTypeID} } eq 'customer' ) {
            $Article->{Direction} = 'Incoming';
        }
        else {
            $Article->{Direction} = 'Outgoing';
        }

        $Article = $Self->_ClearObjectFields(
            Object => $Article,
            Type   => 'Article'
        );
    }

    return {
        Response => "OK",
        Articles => \@Articles
    };
}

sub UpdateQueue {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Self->{TicketObject};

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    if ( $Param{Queue} and !$Param{QueueID} ) {
        $Param{QueueID} = $Kernel::OM->Get('Kernel::System::Queue')
          ->QueueLookup( Queue => $Param{Queue} );
    }

    my $HasMoveIntoPermission = $Self->_CheckGroupPermission(
        QueueID => $Param{QueueID},
        Type    => ['move_into'],
        UserID  => $Param{UserID}
    );

    if ( !$HasMoveIntoPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    my $Success;
    if ( $Ticket{Lock} eq 'unlock' ) {
        $Success = $TicketObject->TicketQueueSet(
            QueueID  => $Param{QueueID},
            TicketID => $Param{TicketID},
            UserID   => $Param{UserID}
        );
    }
    elsif ( $Ticket{Lock} eq 'lock' ) {
        if ( $Ticket{OwnerID} == $Param{UserID} ) {
            $Success = $TicketObject->TicketQueueSet(
                QueueID  => $Param{QueueID},
                TicketID => $Param{TicketID},
                UserID   => $Param{UserID}
            );
        }
        else {
            return {
                Response => "ERROR",
                Message  => "You must be an owner of the ticket"
            };
        }
    }

    if ( !$Success ) {
        return {
            Response => 'ERROR',
            Message  => 'Cannot update Queue'
        };
    }

    return { Response => "OK" };
}

sub UpdateTitle {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Self->{TicketObject};

    # Get Ticket
    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    my $HasPermission = $Self->_CheckGroupPermission(
        QueueID => $Ticket{QueueID},
        UserID  => $Param{UserID}
    );

    if ( !$HasPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    my $Success = $TicketObject->TicketTitleUpdate(
        Title    => $Param{Title},
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !$Success ) {
        return {
            Response => 'ERROR',
            Message  => 'Cannot update Title'
        };
    }

    return { Response => "OK" };
}

sub WatchTicket {
    my ( $Self, %Param ) = @_;

    my $Result;
    my $TicketObject = $Self->{TicketObject};

    if ( !$Param{TicketID} ) {
        return {
            Response => 'ERROR',
            Message  => 'No TicketID'
        };
    }

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    my $HasPermission = $Self->_CheckGroupPermission(
        QueueID => $Ticket{QueueID},
        Type    => ['ro'],
        UserID  => $Param{UserID}
    );

    if ( !$HasPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    if ( $Param{Subscribe} ) {

        my $Success = $TicketObject->TicketWatchSubscribe(
            TicketID    => $Param{TicketID},
            WatchUserID => $Param{UserID},
            UserID      => $Param{UserID}
        );

        if ( $Success ) {

            $Result = {
                Response => 'OK'
            };

        } else {

            $Result = {
                Response => 'ERROR',
                Message  => 'Could not subscribe to ticket'
            };
        }

    } else {

        my $Success = $TicketObject->TicketWatchUnsubscribe(
            TicketID    => $Param{TicketID},
            WatchUserID => $Param{UserID},
            UserID      => $Param{UserID}
        );

        if ( $Success ) {

            $Result = {
                Response => 'OK'
            };

        } else {

            $Result = {
                Response => 'ERROR',
                Message  => 'Could not unsubscribe from ticket'
            };
        }
    }

    return $Result;
}

sub GetAttachment {
    my ( $Self, %Param ) = @_;

    my $Result;
    my $TicketObject = $Self->{TicketObject};
    my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');

    if ( $Param{ TicketID } and !$Param{ ArticleID } ) {

        my @ArticleBoxAll = $ArticleObject->ArticleList(
            TicketID  => $Param{TicketID},
            OnlyFirst => 1
        );

        if ( @ArticleBoxAll ) {
            $Param{ ArticleID } = $ArticleBoxAll[0]{ ArticleID };
        }
#        my %Article = $TicketObject->ArticleFirstArticle(
#            TicketID => $Param{ TicketID }
#        );
#
#        if ( $Article{ ArticleID } ) {
#            $Param{ ArticleID } = $Article{ ArticleID };
#        }
    }

    # get ArticleID
    my $ArticleID = $Param{ArticleID} // 0;
    my $FileID    = $Param{FileID}    // 0;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');

    # check permissions
#    my %Article = $TicketObject->ArticleGet(
#        ArticleID     => $ArticleID,
#        DynamicFields => 0,
#        UserID        => $Param{UserID},
#    );

    my $TicketID = $ArticleObject->TicketIDLookup(
        ArticleID => $ArticleID
    );

    #if ( !$Article{TicketID} ) {
    if ( !$TicketID ) {

        $Result = {
            Response => "ERROR",
            Message  => "No article!",
        };

    } else {

        # check permissions
        my $Access = $TicketObject->TicketPermission(
            Type     => 'ro',
            TicketID => $TicketID,
            UserID   => $Param{UserID}
        );

        if ( !$Access ) {
            $Result = {
                Response => "ERROR",
                Message  => "No attachment!",
            };

        } else {

            my $ArticleBackendObject = $ArticleObject->BackendForArticle(
                TicketID  => $TicketID,
                ArticleID => $ArticleID
            );

            my %Data = $ArticleBackendObject->ArticleAttachment(
                ArticleID => $ArticleID,
                FileID    => $FileID
            );

            if ( !%Data ) {

                $Result = {
                    Response => "ERROR",
                    Message  => "No attachment!",
                };

            } else {

                # Для html вида страницы
                if ( $Data{ContentType} =~ m{text/html} ) {
                    my $TicketNumber = $Kernel::OM->Get('Kernel::System::Ticket')->TicketNumberLookup(
                        TicketID => $TicketID,
                    );

                    # Render article content.
                    my $ArticleContent = $LayoutObject->ArticlePreview(
                        TicketID  => $TicketID,
                        ArticleID => $ArticleID,
                    );

                    if ( !$ArticleContent ) {
                        $Result = {
                            Response => "ERROR",
                            Message  => "No article!",
                        };
                    }

                    my $Content = $LayoutObject->Output(
                        Template => '[% Data.HTML %]',
                        Data     => {
                            HTML => $ArticleContent,
                        },
                    );

                    my %Data = (
                        Content            => $Content,
                        ContentAlternative => '',
                        ContentID          => '',
                        ContentType        => 'text/html; charset="utf-8"',
                        Disposition        => 'inline',
                        FilesizeRaw        => bytes::length($Content),
                    );

                    # get config object
                    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

                    # set download type to inline
                    $ConfigObject->Set(
                        Key   => 'AttachmentDownloadType',
                        Value => 'inline'
                    );

                    # set filename for inline viewing
                    $Data{Filename} = "Ticket-$TicketNumber-ArticleID-$ArticleID.html";

                    my %Article = $ArticleBackendObject->ArticleGet(
                        TicketID      => $TicketID,
                        ArticleID     => $ArticleID,
                        DynamicFields => 0,
                        UserID        => $Param{UserID}
                    );

                    my $LoadExternalImages = 0;

                    # safety check only on customer article
                    if ( !$LoadExternalImages && $Article{SenderType} ne 'customer' ) {
                        $LoadExternalImages = 1;
                    }

                    # generate base url
#                    my $URL = 'Action=AgentTicketAttachment;Subaction=HTMLView'
#                        . ";TicketID=$TicketID;ArticleID=$ArticleID;FileID=";
                    my $URL = 'Action=tickets;Subaction=getAttachment'
                        . ";ArticleID=$ArticleID;FileID=";

                    # replace links to inline images in html content
                    my %AtmBox = $ArticleBackendObject->ArticleAttachmentIndex(
                        ArticleID => $ArticleID,
                    );

                    # reformat rich text document to have correct charset and links to
                    # inline documents
                    %Data = $LayoutObject->RichTextDocumentServe(
                        Data               => \%Data,
                        URL                => $URL,
                        Attachments        => \%AtmBox,
                        LoadExternalImages => $LoadExternalImages,
                    );

                    # if there is unexpectedly pgp decrypted content in the html email (OE),
                    # we will use the article body (plain text) from the database as fall back
                    # see bug#9672
                    if (
                        $Data{Content} =~ m{
                        ^ .* -----BEGIN [ ] PGP [ ] MESSAGE-----  .* $      # grep PGP begin tag
                        .+                                                  # PGP parts may be nested in html
                        ^ .* -----END [ ] PGP [ ] MESSAGE-----  .* $        # grep PGP end tag
                    }xms
                        )
                    {

                        # html quoting
                        $Article{Body} = $LayoutObject->Ascii2Html(
                            NewLine        => $ConfigObject->Get('DefaultViewNewLine'),
                            Text           => $Article{Body},
                            VMax           => $ConfigObject->Get('DefaultViewLines') || 5000,
                            HTMLResultMode => 1,
                            LinkFeature    => 1,
                        );

                        # use the article body as content, because pgp was definitly descrypted if possible
                        $Data{Content} = $Article{Body};
                    }

                    # return html attachment
                    return $LayoutObject->Attachment(
                        %Data,
                        Sandbox => 1,
                    );
                }

=a
TODO: подумать над возвращением
из-за встроенных картинок не работает
                if ( $Data{ Disposition } eq 'inline' ) {
                    my ($Encoding) = $Data{ContentType} =~ m{charset=['"]([a-z0-9-]+)['"]}i;
                    $Encoding //= 'UTF-8';
                    $Data{Content} = Encode::decode(uc $Encoding, $Data{Content});
                }
=cut

                return $LayoutObject->Attachment(%Data, Type => $Data{ Disposition } );
            }
       }
    }

    return $Result;
}

sub CreateAttachment {
    my ( $Self, %Param ) = @_;

    my $Result;
    my $TicketObject  = $Self->{TicketObject};
    my $ArticleObject = $Self->{ArticleObject};

    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');

    my %File = $ParamObject->GetUploadAll( Param => 'File' );
    my $FromForm = 0;
    if ( !%File ) {
        $Param{File} //= {};

        %File = %{ $Param{File} };
    }
    else {
        $FromForm = 1;
    }

    if ( !$File{Content} or !$File{ContentType} or !$File{Filename} ) {
        return {
            Response => 'ERROR',
            Message  => 'No Content, ContentType or Filename parameters'
        };
    }

    if ( $Param{ TicketID } and
        !$Param{ ArticleID } ) {

        my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');
        my @ArticleBoxAll = $ArticleObject->ArticleList(
            TicketID  => $Param{TicketID},
            OnlyFirst => 1
        );

        if ( @ArticleBoxAll ) {
            $Param{ ArticleID } = $ArticleBoxAll[0]{ ArticleID };
        }
        else {
            return {
                Response => "ERROR",
                Message  => "Ticket is incorrect"
            };
        }
    }

    if ( !$Param{TicketID} and $Param{ArticleID} ) {
        $Param{TicketID} = $ArticleObject->TicketIDLookup(
            ArticleID => $Param{ ArticleID }
        );

        if ( !$Param{TicketID} ) {
            return {
                Response => "ERROR",
                Message  => "Article is incorrect"
            }
        }
    }

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    my $HasPermission = $Self->_CheckGroupPermission(
        QueueID => $Ticket{QueueID},
        Type    => ['create', 'note'],
        Op      => 'OR',
        UserID  => $Param{UserID}
    );

    if ( !$HasPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    my $ArticleBackendObject = $ArticleObject->BackendForArticle(
        TicketID  => $Param{TicketID},
        ArticleID => $Param{ArticleID}
    );

    if ( !$ArticleBackendObject ) {
        $Result = {
            Response => "ERROR",
            Message  => "Internal error. Please contact administrator!"
        };
    }

    my $Success = $ArticleBackendObject->ArticleWriteAttachment(
        Content => $FromForm ? $File{Content} : decode_base64( $File{Content} ),
        ContentType => $File{ContentType},
        Filename    => $File{Filename},
        Disposition => 'attachment',
        ArticleID   => $Param{ArticleID},
        UserID      => $Param{UserID}
    );

    if ( $Success ) {

        my %Index = $ArticleBackendObject->ArticleAttachmentIndex(
            ArticleID => $Param{ArticleID}
        );

        my $LastFileID = ( sort { $a <=> $b } keys %Index )[-1];

        my %Attachment = %{ $Index{ $LastFileID } };

        $Attachment{ContentAlternative} ||= undef;
        $Attachment{ContentID}          ||= undef;

        $Result = {
            Response   => "OK",
            Attachment => {
                %Attachment,
                FileID => $LastFileID
            }
        };

    } else {

        $Result = {
            Response => "ERROR",
            Message  => "Cannot add attachment"
        };
    }

    return $Result;
}

sub UpdateCustomer {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Self->{TicketObject};

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    my $HasPermission = $Self->_CheckGroupPermission(
        QueueID => $Ticket{QueueID},
        UserID  => $Param{UserID}
    );

    if ( !$HasPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    my $Success = $TicketObject->TicketCustomerSet(
        No       => $Param{CustomerID},
        User     => $Param{CustomerUserID},
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !$Success ) {
        return {
            Response => 'ERROR',
            Message  => 'Cannot update Customer'
        };
    }

    return { Response => 'OK' };
}

sub UpdateArchiveFlag {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Self->{TicketObject};

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    my $HasPermission = $Self->_CheckGroupPermission(
        QueueID => $Ticket{QueueID},
        UserID  => $Param{UserID}
    );

    if ( !$HasPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    my $Success = $TicketObject->TicketArchiveFlagSet(
        ArchiveFlag => $Param{ArchiveFlag},
        TicketID    => $Param{TicketID},
        UserID      => $Param{UserID}
    );

    if ( !$Success ) {
        return {
            Response => 'ERROR',
            Message  => 'Cannot update ArchiveFlag'
        };
    }

    return { Response => "OK" };
}

sub UpdateState {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Self->{TicketObject};

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    my $HasPermission = $Self->_CheckGroupPermission(
        QueueID => $Ticket{QueueID},
        UserID  => $Param{UserID}
    );

    if ( !$HasPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    my $Success;
    if ( $Ticket{Lock} eq 'unlock' ) {
        $Success = $TicketObject->TicketStateSet(
            State    => $Param{State},
            StateID  => $Param{StateID},
            TicketID => $Param{TicketID},
            UserID   => $Param{UserID}
        );
    }
    elsif ( $Ticket{Lock} eq 'lock' ) {
        if ( $Ticket{OwnerID} == $Param{UserID} ) {
            $Success = $TicketObject->TicketStateSet(
                State    => $Param{State},
                StateID  => $Param{StateID},
                TicketID => $Param{TicketID},
                UserID   => $Param{UserID}
            );
        }
        else {
            return {
                Response => "ERROR",
                Message  => "You must be an owner of the ticket"
            };
        }
    }

    if ( !$Success ) {
        return {
            Response => 'ERROR',
            Message  => 'Cannot update State'
        };
    }
    else {
        my %Ticket = $TicketObject->TicketGet(
            TicketID => $Param{TicketID},
            UserID   => $Param{UserID}
        );

        if ( $Ticket{StateType} eq 'closed' ) {
            my $Success = $TicketObject->TicketLockSet(
                Lock     => 'unlock',
                TicketID => $Param{TicketID},
                UserID   => $Param{UserID}
            );

            if ( !$Success ) {
                return {
                    Response => 'ERROR',
                    Message  => "State has been changed but couldn't unlock Ticket"
                };
            }
        }
    }

    return { Response => "OK" };
}

sub UpdateOwner {
    my ( $Self, %Param ) = @_;

    $Param{Rule} //= '';

    my $TicketObject = $Self->{TicketObject};

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    if (   ( $Param{NewUserID} and $Ticket{OwnerID} == $Param{NewUserID} )
        or ( $Param{NewUser} and $Ticket{Owner} eq $Param{NewUser} ) )
    {
        return {
            Response => 'ERROR',
            Message  => 'Already you are an owner'
        };
    }

    my $HasPermission = $Self->_CheckGroupPermission(
        QueueID => $Ticket{QueueID},
        Type    => ['owner'],
        UserID  => $Param{UserID}
    );

    if ( !$HasPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    if ( defined $Param{NewUserID} and
         $Param{NewUserID} == 0 ) {

        $Param{NewUserID} = $Param{UserID};
    }

    my $Success;
    if ( $Ticket{Lock} eq 'unlock' ) {
        $Success = $TicketObject->TicketOwnerSet(
            NewUser   => $Param{NewUser},
            NewUserID => $Param{NewUserID},
            TicketID  => $Param{TicketID},
            UserID    => $Param{UserID}
        );
    }
    elsif ( $Ticket{Lock} eq 'lock' ) {
        if (   $Ticket{OwnerID} == $Param{UserID}
            or $Param{Rule} eq 'TicketEdit' )
        {
            $Success = $TicketObject->TicketOwnerSet(
                NewUser   => $Param{NewUser},
                NewUserID => $Param{NewUserID},
                TicketID  => $Param{TicketID},
                UserID    => $Param{UserID}
            );
        }
        else {
            return {
                Response => "ERROR",
                Message  => "You must be an owner of the ticket"
            };
        }
    }

    if ( !$Success ) {
        return {
            Response => 'ERROR',
            Message  => 'Cannot update Owner'
        };
    }
    else {

        my $OwnerID = $Param{NewUserID};
        if ( !$OwnerID ) {
            my %Ticket = $TicketObject->TicketGet(
                TicketID => $Param{TicketID},
                UserID   => $Param{UserID}
            );
            $OwnerID = $Ticket{OwnerID};
        }

        my $Success = $TicketObject->TicketLockSet(
            Lock     => 'lock',
            TicketID => $Param{TicketID},
            UserID   => $OwnerID
        );

        if ( !$Success ) {
            return {
                Response => 'ERROR',
                Message  => 'Cannot lock by a new owner'
            };
        }
    }

    return { Response => "OK" };
}

sub UpdateResponsible {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Self->{TicketObject};

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    my $HasPermission = $Self->_CheckGroupPermission(
        QueueID => $Ticket{QueueID},
        UserID  => $Param{UserID}
    );

    if ( !$HasPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    my $Success = $TicketObject->TicketResponsibleSet(
        NewUser   => $Param{NewUser},
        NewUserID => $Param{NewUserID},
        TicketID  => $Param{TicketID},
        UserID    => $Param{UserID}
    );

    if ( !$Success ) {
        return {
            Response => 'ERROR',
            Message  => 'Cannot update Responsible'
        };
    }

    return { Response => "OK" };
}

sub UpdatePriority {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Self->{TicketObject};

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    my $HasPermission = $Self->_CheckGroupPermission(
        QueueID => $Ticket{QueueID},
        Type    => ['priority'],
        UserID  => $Param{UserID}
    );

    if ( !$HasPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    my $Success;
    if ( $Ticket{Lock} eq 'unlock' ) {

        $Success = $TicketObject->TicketPrioritySet(
            Priority   => $Param{Priority},
            PriorityID => $Param{PriorityID},
            TicketID   => $Param{TicketID},
            UserID     => $Param{UserID}
        );
    }
    elsif ( $Ticket{Lock} eq 'lock' ) {
        if ( $Ticket{OwnerID} == $Param{UserID} ) {

            $Success = $TicketObject->TicketPrioritySet(
                Priority   => $Param{Priority},
                PriorityID => $Param{PriorityID},
                TicketID   => $Param{TicketID},
                UserID     => $Param{UserID}
            );
        }
        else {
            return {
                Response => "ERROR",
                Message  => "You must be an owner of the ticket"
            };
        }
    }

    if ( !$Success ) {
        return {
            Response => 'ERROR',
            Message  => 'Cannot update Priority'
        };
    }

    return { Response => "OK" };
}

sub UpdateSLA {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Self->{TicketObject};

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    my $HasPermission = $Self->_CheckGroupPermission(
        QueueID => $Ticket{QueueID},
        UserID  => $Param{UserID}
    );

    if ( !$HasPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    my $Success = $TicketObject->TicketSLASet(
        SLA      => $Param{SLA},
        SLAID    => $Param{SLAID},
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !$Success ) {
        return {
            Response => 'ERROR',
            Message  => 'Cannot update SLA'
        };
    }

    return { Response => "OK" };
}

sub UpdateService {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Self->{TicketObject};

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    my $HasPermission = $Self->_CheckGroupPermission(
        QueueID => $Ticket{QueueID},
        UserID  => $Param{UserID}
    );

    if ( !$HasPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    my $Success = $TicketObject->TicketServiceSet(
        Service   => $Param{Service},
        ServiceID => $Param{ServiceID},
        TicketID  => $Param{TicketID},
        UserID    => $Param{UserID}
    );

    if ( !$Success ) {
        return {
            Response => 'ERROR',
            Message  => 'Cannot update Service'
        };
    }

    return { Response => "OK" };
}

sub UpdateType {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Self->{TicketObject};

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !%Ticket ) {
        return {
            Response => 'ERROR',
            Message  => 'No ticket'
        };
    }

    my $HasPermission = $Self->_CheckGroupPermission(
        QueueID => $Ticket{QueueID},
        UserID  => $Param{UserID}
    );

    if ( !$HasPermission ) {
        return {
            Response => 'ERROR',
            Message  => 'No permission'
        };
    }

    my $Success = $TicketObject->TicketTypeSet(
        Type     => $Param{Type},
        TypeID   => $Param{TypeID},
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID}
    );

    if ( !$Success ) {
        return {
            Response => 'ERROR',
            Message  => 'Cannot update Type'
        };
    }

    return { Response => "OK" };
}

sub _CheckGroupPermission {
    my ( $Self, %Param ) = @_;

    $Param{Op} //= 'AND';

    my $GroupObject = $Self->{GroupObject};

    # Get QueueID
    my $QueueID = $Param{QueueID};

    # Get GroupID from QueueID
    my $GroupID = $Kernel::OM->Get('Kernel::System::Queue')
        ->GetQueueGroupID( QueueID => $Param{ QueueID } );

    # Get GroupName
    my $GroupName = $GroupObject->GroupLookup( GroupID => $GroupID );

    # Check User permissions for a Queue of a ticket
    my $HasPermission = $GroupObject->PermissionCheck(
        UserID    => $Param{UserID},
        GroupName => $GroupName,
        Type      => 'rw'
    );

    # If no RW, check Type array
    if ( !$HasPermission ) {
        if ( $Param{Type} and ref $Param{Type} eq 'ARRAY' ) {

            for my $Permission ( @{ $Param{Type} } ) {
                my $HasPermissionItem = $GroupObject->PermissionCheck(
                    UserID    => $Param{UserID},
                    GroupName => $GroupName,
                    Type      => $Permission
                );

                if ( $Param{Op} eq 'OR' ) {
                    next if !$HasPermissionItem;
                    return 1;
                }
                else {
                    return if !$HasPermissionItem;
                }
            }

            if ( $Param{Op} eq 'OR' ) {
                return;
            }
        }
        else {
            return;
        }
    }

    return 1;
}

sub _ClearObjectFields {
    my ( $Self, %Param ) = @_;

    my $Object = $Param{Object};
    my $Type   = $Param{Type} // 'Ticket';

    my $TypeObject = $Kernel::OM->Get('Kernel::Config')
      ->Get('RS::API::ObjectType');

    my $NumberFields = $TypeObject->{Number};

    for my $FieldName ( @{ $NumberFields } ) {

        if ( defined $Object->{$FieldName} and $Object->{$FieldName} eq '' )
        {
            $Object->{$FieldName} = undef;
        }
    }

    my $DateFields = $TypeObject->{Date};

    for my $FieldName ( @{$DateFields} ) {

        if ( defined $Object->{$FieldName}
            and
            ( $Object->{$FieldName} eq '' or $Object->{$FieldName} eq '0' ) )
        {
            $Object->{$FieldName} = undef;
        }
    }

    if ( $Type eq 'Ticket' ) {

        for my $FieldName (qw/CustomerID/) {
            if ( defined $Object->{$FieldName} and $Object->{$FieldName} eq '' )
            {
                $Object->{$FieldName} = undef;
            }
        }
    }
    elsif ( $Type eq 'Article' ) {

        for my $FieldName (
            qw/
            Bcc
            Cc
            ContentAlternative
            ContentID
            CustomerID
            InReplyTo
            MessageID
            References
            ReplyTo
            To
            CustomerID
            /
          )
        {
            if ( defined $Object->{$FieldName} and $Object->{$FieldName} eq '' )
            {
                $Object->{$FieldName} = undef;
            }
        }
    }

    return $Object;
}

sub _SmartTicketSearch {
    my ( $Self, %Param ) = @_;

    my $OrderBy = 'Up';
    if ( ref $Param{OrderBy} eq 'ARRAY' ) {
        $OrderBy = $Param{OrderBy}[0];
    }
    else {
        $OrderBy = $Param{OrderBy};
    }

    my @TicketIDs = ();

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    my $CurrentDate = strftime "%Y-%m-%d %H:%M:%S", gmtime;

    my @PartTicketIDs = $TicketObject->TicketSearch(
        %Param,
        SortBy => 'EscalationSolutionTime',
        (
            $OrderBy eq 'Up'
            ? ( TicketEscalationSolutionTimeOlderDate => $CurrentDate )
            : ( TicketEscalationSolutionTimeNewerDate => $CurrentDate )
        ),
        SmartSort => 1
    );
    push @TicketIDs, @PartTicketIDs;

    @PartTicketIDs = $TicketObject->TicketSearch(
        %Param,
        SortBy => 'EscalationSolutionTime',
        (
            $OrderBy eq 'Up'
            ? ( TicketEscalationSolutionTimeNewerDate => $CurrentDate )
            : ( TicketEscalationSolutionTimeOlderDate => $CurrentDate )
        ),
        SmartSort => 1
    );
    push @TicketIDs, @PartTicketIDs;

    @PartTicketIDs = $TicketObject->TicketSearch(
        %Param,
        TicketEscalationSolutionTime => 0,
        SortBy                       => 'Age'
    );
    push @TicketIDs, @PartTicketIDs;

    return @TicketIDs;
}

1;

__END__

=encoding utf8

=head1 NAME

Kernel::System::API::Ticket

=head1 DESCRIPTION

=head1 METHODS

=over

=item UpdateQueue

Permission:

=item GetTicketList

Get ticket list of ticket count.

    $APITicketObject->GetTicketList(
        UserID => $UserID,
        Count  => 1|0      # optional, default 1
        %Params            # the same as for _GetTicketRequestParams()
    );

Returns tickets from Queues with Group permissions RO or RW.

Returns:

    {
        NeedTokenUpdate: 1 | 0,
        Response:        $Response,
        Tickets: [
            {
                TicketParam1 => ...,
                ...
            },
            ...
        ]
    }

Sorting. If sort by Escalation.

The order of tickets with straight direction:

1. Expired. From the most to the least ones.
2. Not expired. From the approaching to expired to the least ones.
3. Without expire. By age, from old to new ones.

With reverse direction:

1. Not expired. From the least to the approaching to expired.
2. Expired. From the most to the least ones.
3. Without expire. By age, from new to old ones.

=back

=head2 INTERNAL METHODS

=over

=item _GetTicketRequestParams()

Get parameters from Views for TicketSearch.

    my $Params = $Self->_GetTicketRequestParams(
        ViewID => $ViewID,

        FullTextSearch => $FullTextSearch,
        TicketID       => $TicketID,
        TicketNumber   => $TicketNumber,

        Title       => $Title,
        Queues      => $Queues,
        QueueIDs    => $QueueIDs,
        Types       => $Types,
        TypeIDs     => $TypeIDs,
        States      => $States,
        StateIDs    => $StateIDs,
        StateType   => $StateType,
        Priorities  => $Priorities,
        PriorityIDs => $PriorityIDs,
        Services    => $Services,
        ServiceIDs  => $ServiceIDs,
        SLAs        => $SLAs,
        SLAIDs      => $SLAIDs,

        OwnerIDs          => $OwnerIDs,
        ResponsibleIDs    => $ResponsibleIDs,
        WatchUserIDs      => $WatchUserIDs,
        CustomerID        => $CustomerID,
        CustomerUserLogin => $CustomerUserLogin,

        Locks   => $Locks,
        LockIDs => $LockIDs,

        From    => $From,
        To      => $To,
        Cc      => $Cc,
        Subject => $Subject,
        Body    => $Body,

        SortBy  => $SortBy,
        OrderBy => $OrderBy,

        Result => $Result,

        UserID => $UserID
    );

Returns:

{
    ViewParams  => ...,
    TicketParam => ...
}

=item _GetViewParams()

Get parameters for Filters from Views (and Views package if it is installed).

    my $ViewsArr = $Self->_GetViewParams(
        SortBy  => $SortBy,
        OrderBy => $OrderBy,
        ViewID  => $ViewID,
        UserID  => $UserID
    );

Returns:

[
    {
        the same as parameters from _GetTicketRequestParams()
    },
    ...
]

=back
