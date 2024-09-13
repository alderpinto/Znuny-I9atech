# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
#               2018-2020 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

use strict;
use warnings;

use Data::Dumper;
use Date::Parse;

use LWP::UserAgent;
use JSON::XS;

use vars (qw($Self));

$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase => 0,
    },
);
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
my $ST = $Self->{OriginalSTDOUT};

my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
my $UserObject   = $Kernel::OM->Get('Kernel::System::User');
my $JSONObject   = $Kernel::OM->Get('Kernel::System::JSON');
my $HelperObject = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

my $TestCredits = $ConfigObject->Get('RS::API::Test');

my $URLBase          = $TestCredits->{Domain}.'/otrs/api';
my $TestUserLogin    = $TestCredits->{User};
my $TestUserPassword = $TestCredits->{Password};

my %User = $UserObject->GetUserData(
    User => $TestUserLogin
);

my $ua = LWP::UserAgent->new;

my %AgentCredentials = (
    User     => $TestUserLogin,
    Password => $TestUserPassword
);

my %GlobalAuth = ();

#--------------------------------------------------------------------------------------------------
#
# /auth/login
#
#--------------------------------------------------------------------------------------------------

####################################################################################################
# Успешная авторизация
####################################################################################################

$Self->True(1, '/auth/login - successful authentication');
{
    my $Request = { %AgentCredentials };

    my $JSONString = $JSONObject->Encode( Data => $Request );

    my $req = HTTP::Request->new( 'POST', "$URLBase/auth/login" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;
        if ( $Self->Is( $Response->{Response}, 'OK', 'response ok' ) ) {
            $Self->Is( $Response->{Message}, 'Successful login', 'message ok' );
            $Self->Is( length $Response->{OTRSAgentInterface}, 32, 'token ok' );
            $Self->Is( length $Response->{ChallengeToken}, 32, 'challenge token ok' );
            $Self->Is( $Response->{Settings}{Language}, 'en', 'lang ok' );

            for (qw/ ID FirstName LastName UserLogin Email Avatar FullName /) {
                $Self->True( exists $Response->{Me}{$_}, "$_ ok" );
            }

            $GlobalAuth{ OTRSAgentInterface } = $Response->{ OTRSAgentInterface };
            $GlobalAuth{ ChallengeToken }     = $Response->{ ChallengeToken };
        }
    } else {
        print $ST $Result->status_line;
    }
}

####################################################################################################
# Неудачная авторизация
####################################################################################################

$Self->True(1, '/auth/login - failed authentication');

{
    my $Request = { User => 'abcd', Password => '12345' };

    my $JSONString = $JSONObject->Encode( Data => $Request );

    my $req = HTTP::Request->new( 'POST', "$URLBase/auth/login" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        $Self->Is( $Response->{Response}, 'ERROR', 'response error' );
        $Self->True( $Response->{Message} =~ /^Login failed/, 'message not ok' );
    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /auth/lostPassword
#
#--------------------------------------------------------------------------------------------------

$Self->True(1, '/auth/lostPassword - send email');

{
    
    # TODO: воспроизвести отключение функционала LostPassword
=a
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $CurrentLostPasswordSetting = $ConfigObject->Get('LostPassword');

    $ConfigObject->Set(
        Key   => 'LostPassword',
        Value => 0
    );
=cut

    my $Request = { User => 'asdf@asdf.com' };

    my $JSONString = $JSONObject->Encode( Data => $Request );

    my $req = HTTP::Request->new( 'POST', "$URLBase/auth/lostPassword" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        $Self->Is( $Response->{Response}, 'OK', 'response not ok' );
        $Self->True( $Response->{Message} =~ /^Sent password/, 'message ok' );
    } else {
        print $ST $Result->status_line;
    }
    # TODO: добавить непосредственный вариант для сброса пароля, использую полученный Token
}

#--------------------------------------------------------------------------------------------------
#
# /filters/getTicketViews
#
#--------------------------------------------------------------------------------------------------

$Self->True(1, '/filters/getTicketViews - get ticket views');

{
    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface }
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/filters/getTicketViews" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        $Self->Is( $Response->{Response}, 'OK', 'response ok' );
        $Self->Is( scalar @{ $Response->{Groups} }, 5, 'groups items length' );
    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /queues/getQueueList
#
#--------------------------------------------------------------------------------------------------

$Self->True(1, '/queues/getQueueList - get queue list');

{
    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface }
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/queues/getQueueList" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        $Self->Is( $Response->{Response}, 'OK', 'response ok' );
        $Self->True( scalar @{ $Response->{Queues} }, 'queues length' );

        $Self->True( $Response->{Queues}[0]{ID}, 'queue id' );
        $Self->True( defined $Response->{Queues}[0]{Title}, 'service title' );
    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /services/getServiceList
#
#--------------------------------------------------------------------------------------------------

$Self->True(1, '/services/getServiceList - get service list');

{
    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface }
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/services/getServiceList" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        $Self->Is( $Response->{Response}, 'OK', 'response ok' );
        $Self->True( scalar @{ $Response->{Services} }, 'services length' );

        $Self->True( $Response->{Services}[0]{ID}, 'service id' );
        $Self->True( defined $Response->{Services}[0]{Title}, 'service title' );
    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /sla/getSLAList
#
#--------------------------------------------------------------------------------------------------

$Self->True(1, '/sla/getSLAList - get SLA list');

{
    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface }
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/sla/getSLAList" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        $Self->Is( $Response->{Response}, 'OK', 'response ok' );
        $Self->True( scalar @{ $Response->{ SLAList } }, 'sla list length' );

        $Self->True( $Response->{SLAList}[0]{ID}, 'sla id' );
        $Self->True( defined $Response->{SLAList}[0]{Title}, 'sla title' );
    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /users/getUserList
#
#--------------------------------------------------------------------------------------------------

$Self->True(1, '/users/getUserList - get user list');

{
    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface }
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/users/getUserList" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content; # ибо JSON OTRS работает криво с UTF8

        $Self->Is( $Response->{Response}, 'OK', 'response ok' );
        $Self->True( scalar @{ $Response->{ Users } }, 'user list length' );
        $Self->True( $Response->{ Count }, 'user count' );

        my @UserFields = qw/
            AdminDynamicFieldsOverviewPageShown
            ChangeTime
            CreateTime
            OutOfOffice
            OutOfOfficeEndDay
            OutOfOfficeEndMonth
            OutOfOfficeEndYear
            OutOfOfficeStartDay
            OutOfOfficeStartMonth
            OutOfOfficeStartYear
            UserAuthBackend
            UserChangeOverviewSmallPageShown
            UserComment
            UserConfigItemOverviewSmallPageShown
            UserCreateNextMask
            UserCreateWorkOrderNextMask
            UserEmail
            UserFAQJournalOverviewSmallPageShown
            UserFAQOverviewSmallPageShown
            UserFirstname
            UserFullname
            UserGoogleAuthenticatorSecretKey
            UserID
            UserITSMChangeManagementTemplateEdit
            UserLanguage
            UserLastLogin
            UserLastLoginTimestamp
            UserLastname
            UserLogin
            UserLoginFailed
            UserMobile
            UserPw
            UserRefreshTime
            UserSkin
            UserSurveyOverviewSmallPageShown
            UserTicketOverviewMediumPageShown
            UserTicketOverviewPreviewPageShown
            UserTicketOverviewSmallPageShown
            UserTitle
            ValidID
        /;

        # TODO: уточнить условия при которых они появляются
        my %OptionalFields = (
            AppointmentNotificationTransport     => 1,
            NotificationTransport                => 1,
            OutOfOffice                          => 1,
            OutOfOfficeEndDay                    => 1,
            OutOfOfficeEndMonth                  => 1,
            OutOfOfficeEndYear                   => 1,
            OutOfOfficeStartDay                  => 1,
            OutOfOfficeStartMonth                => 1,
            OutOfOfficeStartYear                 => 1,
            UserComment                          => 1,
            UserGoogleAuthenticatorSecretKey     => 1,
            UserITSMChangeManagementTemplateEdit => 1,
            UserLanguage                         => 1,
            UserMobile                           => 1,
            UserSkin                             => 1
        );

        my $User = $Response->{ Users }[0];

        for ( @UserFields ) {
            if ( !$OptionalFields{$_} ) {
                $Self->True( exists $User->{$_}, "$_ exists" );
            }
        }

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /settings/getLanguageList
#
#--------------------------------------------------------------------------------------------------

$Self->True(1, '/settings/getLanguageList - get language list');

{
    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface }
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/settings/getLanguageList" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        $Self->Is( $Response->{ Response }, 'OK', 'response ok' );
        $Self->True( scalar @{ $Response->{ Languages } }, 'languages list length' );

        $Self->True( $Response->{ Languages }[0]{ID}, 'language id' );
        $Self->True( defined $Response->{ Languages }[0]{Name}, 'language name' );
    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /customers/getCustomerList
#
#--------------------------------------------------------------------------------------------------

$Self->True(1, '/customers/getCustomerList - get customer list');

{
    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface }
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/customers/getCustomerList" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        $Self->Is( $Response->{ Response }, 'OK', 'response ok' );
        $Self->True( scalar @{ $Response->{ CustomerCompanies } }, 'customer companies list length' );

        $Self->True( $Response->{ CustomerCompanies }[0]{ CustomerID }, 'company id' );
        $Self->True( defined $Response->{ CustomerCompanies }[0]{ Name }, 'company name' );
    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /customers/getCustomerUserList
#
#--------------------------------------------------------------------------------------------------

$Self->True(1, '/customers/getCustomerUserList - get customer user list');

{
    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface }
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/customers/getCustomerUserList" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        $Self->Is( $Response->{ Response }, 'OK', 'response ok' );
        $Self->True( scalar @{ $Response->{ CustomerUsers } }, 'customer users list length' );

        $Self->True( $Response->{ CustomerUsers }[0]{ CustomerUser }, 'CustomerUser' );
        $Self->True( defined $Response->{ CustomerUsers }[0]{ Firstname }, 'Firstname' );
        $Self->True( defined $Response->{ CustomerUsers }[0]{ Lastname }, 'Lastname' );
        $Self->True( defined $Response->{ CustomerUsers }[0]{ Avatar }, 'Avatar' );
        $Self->True( defined $Response->{ CustomerUsers }[0]{ Login }, 'Login' );
        $Self->True( defined $Response->{ CustomerUsers }[0]{ Email }, 'Email' );
    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /customers/createCustomerUser
#
#--------------------------------------------------------------------------------------------------

# Успешное создание клиента

$Self->True(1, '/customers/createCustomerUser - create customer user');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    $Kernel::OM->Get('Kernel::System::DB')->Do( SQL => q{
        DELETE FROM customer_user WHERE login = 'ivanivanod'
    });

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        Firstname          => 'Иван',
        Lastname           => 'Иванов',
        CustomerID         => 'ivanivanov ltd',
        Login              => 'ivanivanod',
        Email              => 'ivanov@radiants.ru',
        Password           => 'abcdef',
        Country            => 'Russia',
        City               => 'Moscow',
        Street             => 'pl. Lenina',
        Zip                => 11111,
        Phone              => 22222,
        Mobile             => 33333,
        Fax                => 44444,
        Title              => 'Lord',
        Comment            => 'Hi',
        InterfaceLanguage  => 'ru'
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/customers/createCustomerUser" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {
        use utf8;

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');
            my %User = $CustomerUserObject->CustomerUserDataGet(
                User => 'ivanivanod'
            );

            $Self->Is( $User{ UserFirstname }, 'Иван',               'Firstname'   );
            $Self->Is( $User{ UserLastname  }, 'Иванов',             'Lastname'    );
            $Self->Is( $User{ UserCustomerID}, 'ivanivanov ltd',     'CustomerID'  );
            $Self->Is( $User{ UserLogin     }, 'ivanivanod',         'Login'       );
            $Self->Is( $User{ UserEmail     }, 'ivanov@radiants.ru', 'Email'       );
            $Self->True( defined $User{ UserPassword  },             'Password'    );
            $Self->Is( $User{ UserCountry   }, 'Russia',             'UserCountry' );
            $Self->Is( $User{ UserCity      }, 'Moscow',             'UserCity'    );
            $Self->Is( $User{ UserStreet    }, 'pl. Lenina',         'UserStreet'  );
            $Self->Is( $User{ UserZip       }, 11111,                'UserZip'     );
            $Self->Is( $User{ UserPhone     }, 22222,                'UserPhone'   );
            $Self->Is( $User{ UserMobile    }, 33333,                'UserMobile'  );
            $Self->Is( $User{ UserFax       }, 44444,                'UserFax'     );
            $Self->Is( $User{ UserTitle     }, 'Lord',               'UserTitle'   );
            $Self->Is( $User{ UserComment   }, 'Hi',                 'UserComment' );

            my %Preferences = $CustomerUserObject->GetPreferences(
                UserID => 'ivanivanod'
            );

            $Self->Is( $Preferences{ UserLanguage }, 'ru', 'UserLanguage' );

            $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;
        }

    } else {
        print $ST $Result->status_line;
    }
}

# Пропущен обязательный аргумент при создании клиента

$Self->True(1, '/customers/createCustomerUser - create customer user');

{
    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        Firstname          => 'Иван',
        Lastname           => 'Иванов',
        CustomerID         => 'ivanivanov ltd',
        Email              => 'ivanov@radiants.ru'
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/customers/createCustomerUser" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {
        use utf8;

        my $Response = decode_json $Result->decoded_content;

        $Self->Is( $Response->{ Response }, 'ERROR', 'response error' );
        $Self->Is( $Response->{ Message }, 'Required fields is not defined: Login', 'message' );

    } else {
        print $ST $Result->status_line;
    }
}

# Ошибка при создании клиента

$Self->True(1, '/customers/createCustomerUser - error');

{
    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        Firstname          => 'Иван',
        Lastname           => 'Иванов',
        CustomerID         => 'ivanivanov ltd',
        Email              => 'ivanovradiantsru',
        Login              => 'asdfaaa',
        UserFax            => 'F'x1024
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/customers/createCustomerUser" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {
        use utf8;

        my $Response = decode_json $Result->decoded_content;

        $Self->Is( $Response->{ Response }, 'ERROR', 'response error' );
        $Self->Is( $Response->{ Message }, "Couldn't create customer user", 'message' );

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /customers/getCustomerUser
#
#--------------------------------------------------------------------------------------------------

# Получение клиента

$Self->True(1, '/customers/getCustomerUser - get customer user');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        CustomerUser => 'ivanivanod',
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/customers/getCustomerUser" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {
        use utf8;

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');

            $Self->Is( $Response->{ UserFirstname }, 'Иван',               'Firstname'   );
            $Self->Is( $Response->{ UserLastname  }, 'Иванов',             'Lastname'    );
            $Self->Is( $Response->{ UserCustomerID}, 'ivanivanov ltd',     'CustomerID'  );
            $Self->Is( $Response->{ UserLogin     }, 'ivanivanod',         'Login'       );
            $Self->Is( $Response->{ UserEmail     }, 'ivanov@radiants.ru', 'Email'       );
            $Self->Is( $Response->{ UserCountry   }, 'Russia',             'UserCountry' );
            $Self->Is( $Response->{ UserCity      }, 'Moscow',             'UserCity'    );
            $Self->Is( $Response->{ UserStreet    }, 'pl. Lenina',         'UserStreet'  );
            $Self->Is( $Response->{ UserZip       }, 11111,                'UserZip'     );
            $Self->Is( $Response->{ UserPhone     }, 22222,                'UserPhone'   );
            $Self->Is( $Response->{ UserMobile    }, 33333,                'UserMobile'  );
            $Self->Is( $Response->{ UserFax       }, 44444,                'UserFax'     );
            $Self->Is( $Response->{ UserTitle     }, 'Lord',               'UserTitle'   );
            $Self->Is( $Response->{ UserComment   }, 'Hi',                 'UserComment' );
            $Self->Is( $Response->{ ValidID       }, 1,                    'ValidID'     );

            my %Preferences = $CustomerUserObject->GetPreferences(
                UserID => 'ivanivanod'
            );

            $Self->Is( $Preferences{ UserLanguage }, 'ru', 'UserLanguage' );

            $Kernel::OM->Get('Kernel::System::DB')->Do( SQL => q{
                DELETE FROM customer_user WHERE login = 'ivanivanod'
            });

            $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;
        }

    } else {
        print $ST $Result->status_line;
    }
}

# Создание тестовой заявки

my $TicketID = $TicketObject->TicketCreate(
    Title      => 'TestOneTest',
    Body       => 'OneTestOne',
    State      => 'new',
    Lock       => 'unlock',
    PriorityID => 1,
    QueueID    => 1,
    OwnerID    => 1,
    UserID     => 1
);

#--------------------------------------------------------------------------------------------------
#
# /tickets/updateQueue
#
#--------------------------------------------------------------------------------------------------

# Изменение очереди

$Self->True(1, '/tickets/updateQueue - update queue');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        QueueID            => 2,
        TicketID           => $TicketID
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/updateQueue" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my %Ticket = $TicketObject->TicketGet( TicketID => $TicketID );
            $Self->Is( $Ticket{ QueueID }, 2, 'ticket queue id');
        }

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/updateType
#
#--------------------------------------------------------------------------------------------------

# Изменение типа

$Self->True(1, '/tickets/updateType - update type');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        Type               => 'Problem',
        TicketID           => $TicketID
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/updateType" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my %Ticket = $TicketObject->TicketGet( TicketID => $TicketID );
            $Self->Is( $Ticket{ Type }, 'Problem', 'ticket type');
        }

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/updateService
#
#--------------------------------------------------------------------------------------------------

# Изменение сервиса

$Self->True(1, '/tickets/updateService - update service');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        ServiceID          => 1,
        TicketID           => $TicketID
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/updateService" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my %Ticket = $TicketObject->TicketGet( TicketID => $TicketID );
            $Self->Is( $Ticket{ ServiceID }, 1, 'ServiceID');
        }
    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/updateSLA
#
#--------------------------------------------------------------------------------------------------

# Изменение сервиса

$Self->True(1, '/tickets/updateSLA - update sla');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        SLAID              => 1,
        TicketID           => $TicketID
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/updateSLA" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my %Ticket = $TicketObject->TicketGet( TicketID => $TicketID );
            $Self->Is( $Ticket{ SLAID }, 1, 'SLAID');
        }
    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/updateCustomer
#
#--------------------------------------------------------------------------------------------------

# Изменение клиента

$Self->True(1, '/tickets/updateCustomer - update customer');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        TicketID           => $TicketID,
        CustomerID         => 'abc@radiants.com', # Company
        CustomerUserID     => 'abc@radiants.ru'
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/updateCustomer" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my %Ticket = $TicketObject->TicketGet( TicketID => $TicketID );
            $Self->Is( $Ticket{ CustomerID },     'abc@radiants.com',  'CustomerID' );
            $Self->Is( $Ticket{ CustomerUserID }, 'abc@radiants.ru', 'CustomerUserID' );
        }

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/updatePendingTime
#
#--------------------------------------------------------------------------------------------------

# Изменение клиента

$Self->True(1, '/tickets/updatePendingTime - update pending time');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        TicketID           => $TicketID,
        UntilTimeDateUnix  => str2time('2020-12-31 12:12:12')
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/updatePendingTime" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my %Ticket = $TicketObject->TicketGet( TicketID => $TicketID );
            $Self->True( $Ticket{ RealTillTimeNotUsed } + 1000 > str2time('2020-12-31 12:12:12'), 'UntilTimeDateUnix' );
        }

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/updateLock
#
#--------------------------------------------------------------------------------------------------

# Блокирование заявки

$Self->True(1, '/tickets/updateLock - update lock');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        TicketID           => $TicketID,
        Lock               => 'lock'
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/updateLock" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my %Ticket = $TicketObject->TicketGet( TicketID => $TicketID );
            $Self->Is( $Ticket{Lock}, 'lock', 'Lock' );
            $Self->Is( $Ticket{Owner}, $TestUserLogin, 'Owner' );
        }

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/updateState
#
#--------------------------------------------------------------------------------------------------

# Изменение состояния

$Self->True(1, '/tickets/updateState - update state');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        TicketID           => $TicketID,
        StateID            => 1
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/updateState" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my %Ticket = $TicketObject->TicketGet( TicketID => $TicketID );
            $Self->Is( $Ticket{ StateID }, 1, 'StateID' );
        }

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/updateOwner
#
#--------------------------------------------------------------------------------------------------

# Изменение владельца

$Self->True(1, '/tickets/updateOwner - update owner');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        TicketID           => $TicketID,
        NewUserID          => 2
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/updateOwner" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my %Ticket = $TicketObject->TicketGet( TicketID => $TicketID );
            $Self->Is( $Ticket{ OwnerID }, 2, 'OwnerID' );
        }

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/updateResponsible
#
#--------------------------------------------------------------------------------------------------

# Изменение 

$Self->True(1, '/tickets/updateResponsible - update owner');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        TicketID           => $TicketID,
        NewUserID          => 2
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/updateResponsible" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my %Ticket = $TicketObject->TicketGet( TicketID => $TicketID );
            $Self->Is( $Ticket{ ResponsibleID }, 2, 'ResponsibleID' );
        }

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/updatePriority
#
#--------------------------------------------------------------------------------------------------

# Изменение 

$Self->True(1, '/tickets/updatePriority - update priority');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        TicketID           => $TicketID,
        PriorityID          => 2
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/updatePriority" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my %Ticket = $TicketObject->TicketGet( TicketID => $TicketID );
            $Self->Is( $Ticket{ PriorityID }, 2, 'PriorityID' );
        }

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/updateTicket
#
#--------------------------------------------------------------------------------------------------

# Изменение 

$Self->True(1, '/tickets/updateTicket - update ticket');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        Title              => 'Office',
        TypeID             => 2,
        QueueID            => 2,
        PriorityID         => 2,
        ServiceID          => 1,
        SLAID              => 1,
        CustomerUserID     => 'abc@abc.com',
        CustomerID         => 'abcabc',
        Lock               => 'lock',
        StateID            => 3,
        NewOwnerID         => 1,
        NewResponsibleID   => 2,
        UntilTimeDateUnix  => str2time('2021-12-31 12:12:12'),
        TicketID           => $TicketID
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/updateTicket" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my %Ticket = $TicketObject->TicketGet( TicketID => $TicketID );
            $Self->Is( $Ticket{ Title }, 'Office', 'Title' );
            $Self->Is( $Ticket{ TypeID }, 2, 'TypeID' );
            $Self->Is( $Ticket{ QueueID }, 2, 'QueueID' );
            $Self->Is( $Ticket{ PriorityID }, 2, 'PriorityID' );
            $Self->Is( $Ticket{ ServiceID }, 1, 'ServiceID' );
            $Self->Is( $Ticket{ SLAID }, 1, 'SLAID' );
            $Self->Is( $Ticket{ CustomerUserID }, 'abc@abc.com', 'CustomerUserID' );
            $Self->Is( $Ticket{ CustomerID }, 'abcabc', 'CustomerID' );
            $Self->True( $Ticket{ RealTillTimeNotUsed } + 5000 > str2time('2019-12-31 12:12:12'), 'UntilTimeDateUnix' );
            $Self->Is( $Ticket{ Lock }, 'lock', 'Lock' );
            $Self->Is( $Ticket{ StateID }, 3, 'StateID' );
            $Self->Is( $Ticket{ OwnerID }, 1, 'OwnerID' );
            $Self->Is( $Ticket{ ResponsibleID }, 2, 'ResponsibleID' );
        }

    } else {
        print $ST $Result->status_line;
    }
}

# Изменение неудачно

$Self->True(1, '/tickets/updateTicket - update ticket');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        Lock               => 'asdf',
        TicketID           => $TicketID,
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/updateTicket" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        $Self->Is( $Response->{ Response }, 'ERROR', 'response error' );
        $Self->Is( $Response->{ Message }, "The follow parameters wasn't updated: Lock", 'message');
    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/updateArchiveFlag
#
#--------------------------------------------------------------------------------------------------

# Флаг заявки

=a
# TODO: без настройки Ticket::ArchiveFlag не проверить
$Self->True(1, '/tickets/updateArchiveFlag - update archive flag');

{
    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        TicketID           => $TicketID,
        ArchiveFlag        => 'y'
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/updateArchiveFlag" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = $JSONObject->Decode( Data => $Result->decoded_content );

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my %Ticket = $TicketObject->TicketGet( TicketID => $TicketID );
            $Self->Is( $Ticket{ ArchiveFlag }, 'y', 'ArchiveFlag' );
        }

    } else {
        print $ST $Result->status_line;
    }
}
=cut

#--------------------------------------------------------------------------------------------------
#
# /tickets/getTicketList
#
#--------------------------------------------------------------------------------------------------

# Получить список заявок

$Self->True(1, '/tickets/getTicketList - get ticket list');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/getTicketList" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            $Self->True( scalar @{ $Response->{ Tickets } }, 'tickets length' );
            # TODO: подробный тест для всех случаев
        }

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/createTicket
#
#--------------------------------------------------------------------------------------------------

# Создать заявку

$Self->True(1, '/tickets/createTicket - create ticket');

my $NewTicketID = 0;
{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        Title      => 'Note',
        Body       => 'Book',
        QueueID    => 1,
        PriorityID => 1,

        ArticleType       => 'email',
        SenderType        => 'agent',
        OwnerID           => 1,
        Lock              => 'lock',
        From              => 'system',
        To                => 'dddd@radiants.ru',
        Cc                => 'eeee@radiants.ru',
        ReplyTo           => 'fff@radiants.ru',
        ContentType       => 'text/html',
        CustomerID        => 'ffff',
        CustomerUser      => 'asdf',
        StateID           => 1,
        Estimated         => 10,
        UntilTimeDateUnix => str2time('2020-05-04 12:12:12')
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/createTicket" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            $NewTicketID = $Response->{ TicketID };
            $Self->True( $Response->{ TicketID }, 'ticket id' );
            # TODO: подробный тест для всех случаев
        }

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/createArticle
#
#--------------------------------------------------------------------------------------------------

# Создать заявку

$Self->True(1, '/tickets/createArticle - create article');

my $ArticleID = 0;
{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        Subject   => 'One',
        Body      => 'Two',
        Estimated => 2,
        TicketID  => $TicketID,
        UntilTimeDateUnix  => str2time('2021-12-31 12:12:12')
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/createArticle" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            $ArticleID = $Response->{ ArticleID };
            $Self->True( $Response->{ ArticleID }, 'article id' );
            # TODO: подробный тест для всех случаев
        }

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/getArticles
#
#--------------------------------------------------------------------------------------------------

# Получить заметки

$Self->True(1, '/tickets/getArticles - get articles');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        TicketID           => $TicketID
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/getArticles" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            $Self->True( scalar @{ $Response->{ Articles } }, 'articles' );
            # TODO: подробный тест для всех случаев
        }

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/watchTicket
#
#--------------------------------------------------------------------------------------------------

# Следить

$Self->True(1, '/tickets/watchTicket - watch ticket');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        TicketID           => $TicketID,
        Subscribe          => 1
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/watchTicket" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my @Watchers = $TicketObject->TicketWatchGet(
                TicketID => $TicketID,
                Result   => 'ARRAY'
            );
            $Self->Is( $Watchers[0], $User{UserID}, 'watcher' );
        }

    } else {
        print $ST $Result->status_line;
    }
}

# Не следить

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        TicketID           => $TicketID,
        Subscribe          => 0
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/watchTicket" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my @Watchers = $TicketObject->TicketWatchGet(
                TicketID => $TicketID,
                Result   => 'ARRAY'
            );
            $Self->True( !@Watchers, 'no watchers' );
        }

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/markTicketAsSeen
#
#--------------------------------------------------------------------------------------------------

# Следить

$Self->True(1, '/tickets/markTicketAsSeen - mark ticket');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        TicketID           => $TicketID,
        Seen               => 1
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/markTicketAsSeen" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my %Flags = $TicketObject->TicketFlagGet(
                TicketID => $TicketID,
                UserID   => $User{UserID}
            );
            $Self->True( $Flags{ Seen }, 'ticket seen');
        }

    } else {
        print $ST $Result->status_line;
    }
}

# Не следить

$Self->True(1, '/tickets/markTicketAsSeen - mark ticket');

{
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        TicketID           => $TicketID,
        Seen               => 0
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/markTicketAsSeen" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            my %Flags = $TicketObject->TicketFlagGet(
                TicketID => $TicketID,
                UserID   => $User{UserID}
            );
            $Self->True( !$Flags{ Seen }, 'ticket not seen');
        }

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /tickets/markArticleAsSeen
#
#--------------------------------------------------------------------------------------------------

# Прочитанная заметка

$Self->True(1, '/tickets/markArticleAsSeen - mark article');

for my $Seen (0,1) {
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        ArticleID          => $ArticleID,
        Seen               => $Seen
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );
    my $req = HTTP::Request->new( 'POST', "$URLBase/tickets/markArticleAsSeen" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {

        my $Response = decode_json $Result->decoded_content;

        if ( $Self->Is( $Response->{ Response }, 'OK', 'response ok' ) ) {
            if ( $Self->True( $Response->{ TicketID }, 'ticket id') ) {
                my %Flags = $TicketObject->TicketFlagGet(
                    TicketID => $Response->{ TicketID },
                    UserID   => $User{UserID}
                );
                $Self->Is( $Response->{ TicketSeen }, $Flags{ Seen }, "ticket seen $Seen");
            }
        }

    } else {
        print $ST $Result->status_line;
    }
}

#--------------------------------------------------------------------------------------------------
#
# /auth/logout
#
#--------------------------------------------------------------------------------------------------

####################################################################################################
# Просроченная сессия
####################################################################################################

$Self->True(1, '/auth/logout - failed session');

{
    my $Request = { };

    my $JSONString = $JSONObject->Encode( Data => $Request );

    my $req = HTTP::Request->new( 'POST', "$URLBase/auth/logout" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {
        use utf8;

        my $Response = decode_json $Result->decoded_content;

        $Self->Is( $Response->{Response}, 'ERROR', 'response error' );
        $Self->True( $Response->{Message} =~ /^Session invalid/, 'message not ok' );
    } else {
        print $ST $Result->status_line;
    }
}

####################################################################################################
# Неправильный ChallengeToken
####################################################################################################

$Self->True(1, '/auth/logout - wrong ChallengeToken');

{
    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface }
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );

    my $req = HTTP::Request->new( 'POST', "$URLBase/auth/logout" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {
        use utf8;

        my $Response = decode_json $Result->decoded_content;

        $Self->Is( $Response->{Response}, 'ERROR', 'response error' );
        $Self->True( $Response->{Message} =~ /^Invalid Challenge Token/, 'message not ok' );
    } else {
        print $ST $Result->status_line;
    }
}

####################################################################################################
# Успешный выход
####################################################################################################

$Self->True(1, '/auth/logout - successful logout');

{
    my $Request = {
        OTRSAgentInterface => $GlobalAuth{ OTRSAgentInterface },
        ChallengeToken     => $GlobalAuth{ ChallengeToken }
    };

    my $JSONString = $JSONObject->Encode( Data => $Request );

    my $req = HTTP::Request->new( 'POST', "$URLBase/auth/logout" );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $JSONString );

    my $Result = $ua->request( $req );

    if ($Result->is_success) {
        use utf8;

        my $Response = decode_json $Result->decoded_content;

        $Self->Is( $Response->{Response}, 'OK', 'response ok' );
        $Self->True( $Response->{Message} =~ /^Logout successful\./, 'message ok' );
    } else {
        print $ST $Result->status_line;
    }
}

my $True = $TicketObject->TicketDelete(
    TicketID => $TicketID,
    UserID   => 1,
);

$True = $TicketObject->TicketDelete(
    TicketID => $NewTicketID,
    UserID   => 1,
);

$Kernel::OM->Get('Kernel::System::Cache')->CleanUp;

1;
