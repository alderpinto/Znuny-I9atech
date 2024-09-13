package Kernel::System::Ticket::Event::CheckInstalledPackage;

use strict;
use warnings;
use utf8;

our @ObjectDependencies = (
    'Kernel::System::Log',
    'Kernel::System::Ticket',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    for (qw(Data Event Config)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    my $MinimalVersion = '6.1.24';

    if ( $Param{Event} =~ /Package(Install|Upgrade|Reinstall)/ ) {
        if ( $Param{Data}{Name} eq 'RS4OTRS_AdvancedTicketSearch'
            and version->parse( $Param{Data}{Version} ) >=
            version->parse($MinimalVersion) )
        {
            $Self->ToggleAutoloadModule( Toggle => 0 );
        }
    }
    elsif ( $Param{Event} eq 'PackageUninstall' ) {
        if ( $Param{Data}{Name} eq 'RS4OTRS_AdvancedTicketSearch'
            and version->parse( $Param{Data}{Version} ) >=
            version->parse($MinimalVersion) )
        {
            $Self->ToggleAutoloadModule( Toggle => 1 );
        }
    }

    return 1;
}

sub ToggleAutoloadModule {
    my ( $Self, %Param ) = @_;

    my $AutoloadTicketSearchName =
      'AutoloadPerlPackages###1100-RS_TicketSearch';

    my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');

    # Getting autoload module param for TicketSearch
    my %AutoloadTicketSearchParam =
      $SysConfigObject->SettingGet( Name => $AutoloadTicketSearchName );

    # Lock it for changing
    my $ExclusiveLockGUID = $SysConfigObject->SettingLock(
        DefaultID => $AutoloadTicketSearchParam{DefaultID},
        Force     => 1,
        UserID    => 1
    );

    if ( !$ExclusiveLockGUID ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Cannot lock $AutoloadTicketSearchName!"
        );
        return;
    }

    my %SettingUpdateResult = $SysConfigObject->SettingUpdate(
        Name              => $AutoloadTicketSearchName,
        IsValid           => 1,
        UserID            => 1,
        ExclusiveLockGUID => $ExclusiveLockGUID,
        EffectiveValue    => $Param{Toggle}
        ? $AutoloadTicketSearchParam{DefaultValue}
        : []
    );

    if ( !$SettingUpdateResult{Success} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Cannot lock $AutoloadTicketSearchName!"
        );
        return;
    }

    my %DeployResult = $SysConfigObject->ConfigurationDeploy( UserID => 1 );

    if ( !$DeployResult{Success} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Cannot deploy configuration $DeployResult{Error}!"
        );
        return;
    }

    return 1;
}

1;
