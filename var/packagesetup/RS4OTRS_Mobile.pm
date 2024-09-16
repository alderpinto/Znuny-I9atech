# --
# Copyright (C) 2020 Radiant System, http://radiantsystem.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package var::packagesetup::RS4OTRS_Mobile;

use strict;
use warnings;

use Data::Dumper;

our @ObjectDependencies = ();

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub CodeInstall {
    my ( $Self, %Param ) = @_;

    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
    $CacheObject->CleanUp(
        Type => 'Mobile'
    );

    $Self->_AddMobileActionsToACLPossibleActionsList();

    my $WebserviceName = 'AndroidNotification';
    my $YAMLObject = $Kernel::OM->Get('Kernel::System::YAML');

    my $WebserviceObject =
        $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice');

    my $Webservice = $WebserviceObject->WebserviceGet(
        Name => $WebserviceName
    );

    if ( %{ $Webservice } ) {

        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Webservice $WebserviceName exists already!",
        );
        return 0;
    }

    my $Home     = $Kernel::OM->Get('Kernel::Config')->Get('Home');
    my $YamlPath = "$Home/var/webservices/AndroidNotification.yml";

    my $YamlContentRef = $Kernel::OM->Get('Kernel::System::Main')->FileRead(
        Location => $YamlPath
    );

    if ( !$YamlContentRef ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Cannot read $YamlPath!",
        );
        return 0;
    }

    my $ConfigHashRef = $YAMLObject->Load( Data => $$YamlContentRef );

    my $ID = $WebserviceObject->WebserviceAdd(
        Name    => $WebserviceName,
        Config  => $ConfigHashRef,
        ValidID => 1,
        UserID  => 1
    );

    if ( !$ID ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Cannot create $WebserviceName!",
        );
        return 0;
    }

    return 1;
}

sub CodeUninstall {
    my ( $Self, %Param ) = @_;

    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
    $CacheObject->CleanUp(
        Type => 'Mobile'
    );

    $Self->_RemoveMobileActionsFromACLPossibleActionsList();

    return 1;
}

sub CodeUpgrade {
    my ( $Self, %Param ) = @_;

    $Self->_AddMobileActionsToACLPossibleActionsList();

    return 1;
}

sub _AddMobileActionsToACLPossibleActionsList {
    my ( $Self, %Param ) = @_;

    my $SettingName = 'ACLKeysLevel3::Actions';
    my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');

    my $DefaultACLActionsListConfig = $Kernel::OM->Get('Kernel::Config')->Get($SettingName);
    my $DefaultACLActionsList = $DefaultACLActionsListConfig->{'100-Default'};

    my %RequiredActions = (
        AgentMobileTicketNote   => 0,
        AgentMobileNewTicket    => 0,
        AgentMobileTicketStatus => 0,
        AgentMobileTicketClose  => 0,
        AgentMobileEditTicket   => 0
    );

    for my $Action ( @{ $DefaultACLActionsList } ) {
        if ( exists $RequiredActions{ $Action } ) {
            $RequiredActions{ $Action } = 1;
        }
    }

    my @MissingActions = grep { !$RequiredActions{$_} } keys %RequiredActions;
    my @ResultActions = ( @{ $DefaultACLActionsList }, @MissingActions );

    my $ExclusiveLockGUID = $SysConfigObject->SettingLock(
        Name    => $SettingName.'###100-Default',
        LockAll => 1,
        Force   => 1,
        UserID  => 1
    );

    if ( !$ExclusiveLockGUID ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Cannot lock SysConfig for setting '$SettingName'!"
        );
        return;
    }

    my %UpdateResult = $SysConfigObject->SettingUpdate(
        Name              => $SettingName.'###100-Default',
        EffectiveValue    => \@ResultActions,
        IsValid           => 1,
        ExclusiveLockGUID => $ExclusiveLockGUID,
        UserID            => 1,
        NoValidation      => 1
    );

    if ( !$UpdateResult{Success} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Cannot update SysConfig for setting '$SettingName': $UpdateResult{Error}"
        );
        return;
    }

    my %DeployResult = $SysConfigObject->ConfigurationDeploy(
        Comments => 'Package RS4OTRS_Mobile: added Mobile ACL Actions',
        UserID => 1,
        Force  => 1
    );

    if ( !$DeployResult{Success} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Cannot update SysConfig for setting '$SettingName': $DeployResult{Error}"
        );
        return;
    }

    return;
}

sub _RemoveMobileActionsFromACLPossibleActionsList {
    my ( $Self, %Param ) = @_;

    my $SettingName = 'ACLKeysLevel3::Actions';
    my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');

    my $DefaultACLActionsListConfig = $Kernel::OM->Get('Kernel::Config')->Get($SettingName);
    my $DefaultACLActionsList = $DefaultACLActionsListConfig->{'100-Default'};

    my %RequiredActions = (
        AgentMobileTicketNote   => 0,
        AgentMobileNewTicket    => 0,
        AgentMobileTicketStatus => 0,
        AgentMobileTicketClose  => 0,
        AgentMobileEditTicket   => 0
    );

    my @ResultActions = ();
    for my $Action ( @{ $DefaultACLActionsList } ) {
        if ( not exists $RequiredActions{ $Action } ) {
            push @ResultActions, $Action;
        }
    }

    my $ExclusiveLockGUID = $SysConfigObject->SettingLock(
        Name    => $SettingName.'###100-Default',
        LockAll => 1,
        Force   => 1,
        UserID  => 1
    );

    if ( !$ExclusiveLockGUID ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Cannot lock SysConfig for setting '$SettingName'!"
        );
        return;
    }

    my %UpdateResult = $SysConfigObject->SettingUpdate(
        Name              => $SettingName.'###100-Default',
        EffectiveValue    => \@ResultActions,
        IsValid           => 1,
        ExclusiveLockGUID => $ExclusiveLockGUID,
        UserID            => 1,
        NoValidation      => 1
    );

    if ( !$UpdateResult{Success} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Cannot update SysConfig for setting '$SettingName': $UpdateResult{Error}"
        );
        return;
    }

    my %DeployResult = $SysConfigObject->ConfigurationDeploy(
        Comments => 'Package RS4OTRS_Mobile: removed Mobile ACL Actions',
        UserID => 1,
        Force  => 1
    );

    if ( !$DeployResult{Success} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Cannot update SysConfig for setting '$SettingName': $DeployResult{Error}"
        );
        return;
    }

    return;
}

1;
