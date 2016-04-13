param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$SlackToken=$(throw "SlackToken is mandatory, please provide a value.")
    ,[Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$SQLHost=$(throw "SQLHost is mandatory, please provide a value. (ex. 10.1.12.3)")
    ,[Parameter()]
    [String]$SQLDatabase="SlackDW"
    ,[Parameter()]
    [Switch]$Reprocess
)

# Import our trusty SQLPS module
Push-Location
Import-Module SQLPS -DisableNameChecking
Pop-Location

##################### Slack Settings ################################
$slackBaseURL = "https://slack.com/api"
$tokenAppend = "?token=$SlackToken"

$userListEndPoint = "$slackBaseURL/users.list$tokenAppend"
$channelListEndPoint = "$slackBaseURL/channels.list$tokenAppend"
$reactionListEndPoint = "$slackBaseURL/reactions.list$tokenAppend&full=1&count=1000&page={0}&user={1}"
$userGroupsEndPoint = "$slackBaseURL/usergroups.list$tokenAppend&include_users=1&include_disabled=1"
$searchEndPoint = "$slackBaseURL/search.messages$tokenAppend&query=in:{0},{1}"
$channelHistoryEndPoint = "$slackBaseURL/channels.history$tokenAppend&count=500&channel={0}&oldest={1}&latest={2}"
$starsByUserEndPoint = "$slackBaseURL/stars.list$tokenAppend&user={0}&count=1000&page={1}"

##################### DW Settings ###################################
$UnknownValue = "Unknown"


##################### GET functions ###############################
Function Get-UserList {
    $json = ConvertFrom-Json (Invoke-WebRequest $userListEndPoint).Content

    If ($json.ok -eq 'true') {
        return $json.members
    }
    Else {
        Throw "An error occured when retrieving the Slack members."
        Exit 1
    }
}


Function Get-ChannelList {
    $json = ConvertFrom-Json (Invoke-WebRequest $channelListEndPoint).Content

    If ($json.ok -eq 'true') {
        return $json.channels
    }
    Else {
        Throw "An error occured when retrieving the Slack channels."
        Exit 1
    }
}


Function Get-UserGroups {
    $json = ConvertFrom-Json (Invoke-WebRequest $userGroupsEndPoint).Content

    If ($json.ok -eq 'true') {
        return $json.usergroups
    }
    Else {
        Throw "An error occured when retrieving the Slack user groups."
        Exit 1
    }
}


Function Get-MessagesByChannel-Search {
    param (
        [String]$ChannelName,
        [String]$Search
    )
    $search = $searchEndPoint -f $ChannelName, $Search
    $json = ConvertFrom-Json (Invoke-WebRequest $search).Content

    If ($json.ok -eq 'true') {
        return $json
    }
    Else {
        Write-Error  "An error occured when retrieving the Slack search for $Search in $ChannelName."
        Throw "An error occured when retrieving the Slack search for $Search in $ChannelName."
        Exit 1
    }
}

Function Get-MessagesByChannel-Incremental {
    param (
        [String]$ChannelID,
        [String]$Oldest = 0, # Default to 0
        [String]$Latest = (New-TimeSpan -Start $(Get-Date -Date "01/01/1970") -End $(Get-Date)).TotalSeconds
    )
    $history = $channelHistoryEndPoint -f $ChannelID, $Oldest, $Latest
    $json = ConvertFrom-Json (Invoke-WebRequest $history).Content

    If ($json.ok -eq 'true') {
        return $json
    }
    Else {
        Write-Error "An error occured when retrieving the Slack channel $channelID messages."
        Throw "An error occured when retrieving the Slack channel $channelID messages."
        Exit 1
    }
}

Function Get-StarsByUser {
    param (
        [String]$User, 
        [Int]$Page
    )

    $formattedURL = $starsByUserEndPoint -f $User, $Page
    $json = ConvertFrom-Json (Invoke-WebRequest $formattedURL).Content

    If ($json.ok -eq 'true') {
        return $json
    }
    Else {
        Throw "An error occured when retrieving the Slack stars by User: $user, and Page: $page.."
        Exit 1
    }

}


#################### STAGE functions ###############################
Function Load-UserList {
    Write-Host "Loading user list..." -NoNewLine -ForegroundColor "Yellow"
    $merge = "
        MERGE dbo.Member t
        USING (
            SELECT
                '{0}' as [Name],
                '{1}' as [ID],
                '{2}' as [IsDeleted],
                '{3}' as [RealName],
                '{4}' as [TimeZone],
                '{5}' as [Email],
                '{6}' as [ImageURL],
                '{7}' as [IsAdmin],
                '{8}' as [IsOwner],
                '{9}' as [IsPrimaryOwner],
                '{10}' as [IsBot]
        ) s
        ON (s.ID = t.ID)
        WHEN NOT MATCHED THEN
            INSERT (Name, ID, IsDeleted, RealName, TimeZone, Email, ImageURL, IsAdmin, IsOwner, IsPrimaryOwner, IsBot)
            VALUES (s.Name, s.ID, s.IsDeleted, s.RealName, s.TimeZone, s.Email, s.ImageURL, s.IsAdmin, s.IsOwner, s.IsPrimaryOwner, s.IsBot)
        WHEN MATCHED THEN
            UPDATE
            SET  Name = s.Name
                , ID = s.ID
                , IsDeleted = s.IsDeleted
                , RealName = s.RealName
                , TimeZone = s.TimeZone
                , Email = s.Email
                , ImageURL = s.ImageURL
                , IsAdmin = s.IsAdmin
                , IsOwner = s.IsOwner
                , IsPrimaryOwner = s.IsPrimaryOwner
                , IsBot = s.IsBot
        ;
    "
    $members = Get-UserList
    ForEach ($m in $members) {
        $query = $merge -f $m.name,$m.id,$m.is_deleted,$m.real_name,$m.tz,$m.profile.email,$m.profile.image_512,$m.is_admin,$m.is_owner,$m.is_primary_owner,$m.is_bot
        Exec-SQL -Query $query
    }
    # Load Unkown record
    $query = $merge -f $UnknownValue,$UnknownValue,$UnknownValue,$UnknownValue,$UnknownValue,$UnknownValue,$UnknownValue,$UnknownValue,$UnknownValue,$UnknownValue,$UnknownValue
    Exec-SQL -Query $query
    Write-Host " Complete" -ForegroundColor "Green"
}


Function Load-ChannelList {
    Write-Host "Loading channel list..." -NoNewLine -ForegroundColor "Yellow"
    $ChannelMerge = "
        MERGE dbo.Channel t
        USING (
            SELECT
                '{0}' as [Name],
                '{1}' as [ID],
                '{2}' as [IsDeleted],
                '{3}' as [EpochCreateDate],
                '{4}' as [CreatorMemberID],
                '{5}' as [IsArchived],
                '{6}' as [IsGeneral],
                '{7}' as [IsMember],
                '{8}' as [Topic],
                '{9}' as [TopicCreatorMemberID],
                '{10}' as [Purpose],
                '{11}' as [PurposeCreatorMemberID]
        ) s
        ON (s.ID = t.ID)
        WHEN NOT MATCHED THEN
            INSERT (Name, ID, IsDeleted, EpochCreateDate, CreatorMemberID, IsArchived, IsGeneral, IsMember, Topic, TopicCreatorMemberID, Purpose, PurposeCreatorMemberID)
            VALUES (s.Name, s.ID, s.IsDeleted, s.EpochCreateDate, s.CreatorMemberID, s.IsArchived, s.IsGeneral, s.IsMember, s.Topic, s.TopicCreatorMemberID, s.Purpose, s.PurposeCreatorMemberID)
        WHEN MATCHED THEN
            UPDATE
            SET  Name = s.Name
                , ID = s.ID
                , IsDeleted = s.IsDeleted
                , EpochCreateDate = s.EpochCreateDate
                , CreatorMemberID = s.CreatorMemberID
                , IsArchived = s.IsArchived
                , IsGeneral = s.IsGeneral
                , IsMember = s.IsMember
                , Topic = s.Topic
                , TopicCreatorMemberID = s.TopicCreatorMemberID
                , Purpose = s.Purpose
                , PurposeCreatorMemberID = s.PurposeCreatorMemberID
        ;
    "
    $ChannelMemberInsert = "
        INSERT INTO [dbo].[ChannelMember] (MemberID, ChannelID)
        VALUES ('{0}', '{1}');
    "
    Truncate-Table '[dbo].[ChannelMember]';

    $channels = Get-ChannelList

    ForEach ($c in $channels) {
        If($c.members.count -gt 0) {
            ForEach ($m in $c.members) {
                $insert = $ChannelMemberInsert -f $m, $c.id
                Exec-SQL -Query $insert
            }
        }
        $query = $ChannelMerge -f $c.name,$c.id,$c.is_deleted,$c.created,$c.creator,$c.is_archived,$c.is_general,$c.is_member,($c.topic.value -replace "'", "''"),$c.topic.creator,($c.purpose.value -replace "'", "''"), $c.purpose.creator
        Exec-SQL -Query $query
    }
    # Load Unknown Values
    $query = $ChannelMerge -f $UnknownValue,$UnknownValue,$UnknownValue,'0',$UnknownValue,$UnknownValue,$UnknownValue,$UnknownValue,$UnknownValue,$UnknownValue,$UnknownValue,$UnknownValue
    Exec-SQL -Query $query

    Write-Host " Complete" -ForegroundColor "Green"
}


Function Load-UserGroups {
    Write-Host "Loading user groups..." -NoNewLine -ForegroundColor "Yellow"
    Truncate-Table '[dbo].[UserGroup]';
    Truncate-Table  '[dbo].[MemberUserGroup]';
    Truncate-Table '[dbo].[ChannelUserGroup]';

    $insertGroup = "
        INSERT INTO [dbo].[UserGroup] (ID, Name, Description, Handle)
        VALUES ('{0}', '{1}', '{2}', '{3}')
    "
    $insertMemUserGroup = "
        INSERT INTO [dbo].[MemberUserGroup] (MemberID, UserGroupID)
        VALUES ('{0}', '{1}')
    "
    $insertChannelUserGroup = "
        INSERT INTO [dbo].[ChannelUserGroup] (ChannelID, UserGroupID)
        VALUES ('{0}', '{1}')
    "
    $groups = Get-UserGroups
    ForEach ($group in $groups) {
        $groupID = $group.id
        $insert = $insertGroup -f $groupID, $group.name, $group.description, $group.handle
        Exec-SQL -Query $insert

        ForEach ($channel in $group.prefs.channels) {
            $insert = $insertChannelUserGroup -f $channel, $groupID
            Exec-SQL -Query $insert
        }

        ForEach ($user in $group.users) {
            $insert = $insertMemUserGroup -f $user, $groupID
            Exec-SQL -Query $insert
        }
    }
    Write-Host " Complete" -ForegroundColor "Green"
}


Function Load-Messages-Reactions {
    param([Switch]$Full) 

    # Current EpochTimeStamp
    [String]$ProcessStartLatest = (New-TimeSpan -Start $(Get-Date -Date "01/01/1970") -End $(Get-Date)).TotalSeconds

    If ($Full) {
        Truncate-Table 'dbo.FactMessage';
        Truncate-Table 'dbo.FactReaction';
        Truncate-Table 'dbo.ProcessMessageLog';
        # For full use 0 as the furthest in history we want to go
        [String]$ProcessStartOldest = '0'
    }
    Else {
        [String]$ProcessStartLatest = (New-TimeSpan -Start $(Get-Date -Date "01/01/1970") -End $(Get-Date)).TotalSeconds
        # Get Last Latest Process Date
        [String]$ProcessStartOldest = (Get-MaxProcessDate)
    }

    $ChannelList = Channel-List

    $MergeMessage = "
        MERGE dbo.FactMessage t
        USING (
            SELECT
                '{0}' as EpochTimeStamp,
                '{1}' as MemberID,
                '{2}' as Text,
                '{3}' as ChannelID
        ) s
        ON (t.ChannelID = s.ChannelID AND t.MemberID = s.MemberID AND t.EpochTimeStamp = s.EpochTimeStamp)
        WHEN NOT MATCHED THEN
            INSERT (EpochTimeStamp, MemberID, Text, ChannelID)
            VALUES ('{0}', '{1}', '{2}', '{3}')
        WHEN MATCHED THEN
            UPDATE
            SET EpochTimeStamp = s.EpochTimeStamp,
                MemberID = s.MemberID,
                Text = s.Text,
                ChannelID = s.ChannelID
        OUTPUT inserted.RID
        ;
    "

    $MergeReaction = "
        MERGE dbo.FactReaction t
        USING (
            SELECT
                '{0}' as MessageRID,
                '{1}' as Name,
                '{2}' as MemberID
        ) s
        ON (s.MessageRID = t.MessageRID AND s.Name = t.Name AND s.MemberID = t.MemberID)
        WHEN NOT MATCHED THEN
            INSERT (MessageRID, Name, MemberID)
            VALUES (s.MessageRID, s.Name, s.MemberID)
        WHEN MATCHED THEN
            UPDATE
            SET MessageRID = s.MessageRID,
                Name = s.Name,
                MemberID = s.MemberID
        ;
    "

    ForEach ($channel in $ChannelList) {
        Write-Host "Loading all messages from channel id: $channel..." -NoNewLine -ForegroundColor "Yellow"
        [String]$hasMore = 'true'
        [String]$latest = $ProcessStartLatest
        [String]$oldest = $ProcessStartOldest
        [String]$Errors = ""
        do {
            $json = Get-MessagesByChannel-Incremental -ChannelID $channel -Latest $latest -Oldest $oldest
            # We need to store the last timestamp for calling the rest of the pages incrementally
            $latest = $json.messages[-1].ts

            # Get the has_more
            [String]$hasMore = $json.has_more

            ForEach ($message in $json.messages) {
                If ($message.type -eq 'message') {
                    $mergeM = $MergeMessage -f $message.ts, $message.user, $(Sanitize-String $message.text), $channel
                    Try {
                        $MessageRID = $(Exec-SQL -Query $mergeM).RID
                    }
                    Catch {
                        # Single quotes causing issues
                        Try {
                            $mergeM = $MergeMessage -f $message.ts, $message.user, $((Sanitize-String $message.text) -replace "'",""), $channel
                            $MessageRID = $(Exec-SQL -Query $mergeM).RID
                        }
                        Catch {
                            $mergeM = $MergeMessage -f $message.ts, $message.user, $UnknownValue, $channel
                            $MessageRID = $(Exec-SQL -Query $mergeM).RID
                            $Errors += "Error sanitizing the message text, marking as $UnknownValue. See RID = $MessageRID for details on the message. `r`n"
                        }
                    }

                    ForEach ($r in $message.reactions) {
                        $ReactionName = $r.name
                        ForEach ($u in $r.users) {
                            $mergeR = $MergeReaction -f $MessageRID, $ReactionName, $u
                            Exec-SQL -Query $mergeR
                        }
                    }
                    
                }
            } 
        } while ($hasMore -eq 'true')
        Write-Host " Complete" -ForegroundColor "Green"
        If ($Errors) {
            Write-Host $Errors -ForegroundColor "Red"
        }
    }

    $insertLatest = "INSERT INTO dbo.ProcessMessageLog (EpochTimeStamp) VALUES ('$ProcessStartLatest');"
    Exec-SQL -Query $insertLatest

}



Function Load-Stars-ByUser {
    Truncate-Table 'dbo.FactStar';
    $members = Member-List

    Write-Host "Loading user starred items..." -ForegroundColor "Yellow" -NoNewLine

    $InsertStarredMessage = "
        INSERT INTO [dbo].FactStar (MemberID, StarType, ChannelID, EpochTimeStamp, MessageMemberID)
        VALUES ('{0}', '{1}', '{2}', '{3}', '{4}');
    "
    $InsertStarredChannel = "
        INSERT INTO [dbo].FactStar (MemberID, StarType, ChannelID)
        VALUES ('{0}', '{1}', '{2}');
    "

    ForEach ($memberID in $members) {
        $currentPage = 1
        do {
            $json = Get-StarsByUser -User "$memberID" -Page $currentPage
            
            If ($json.paging.count -ne 0) {
                ForEach ($item in $json.items) {
                    If ($item.type -eq 'channel') {
                        $insertChannel = $InsertStarredChannel -f $memberID, $item.type, $item.channel, $UnknownValue, $UnknownValue
                        Exec-SQL -Query $insertChannel
                    }
                    ElseIf ($item.type -eq 'message' -and $item.message.type -eq 'message') {
                        $insertMessage = $InsertStarredMessage -f $memberID, $item.type, $item.channel, $item.message.ts, $item.message.user
                        Exec-SQL -Query $insertMessage
                    }
                }
                
                
            }
    
            $currentPage += 1
            $maxPage = $json.paging.pages
        } while ($currentPage -lt $maxPage)

    }

    Write-Host " Complete" -ForegroundColor "Green"
}


################## Helper Functions ###########################
Function Exec-SQL {
    param([String]$Query)
    # Very important to use DisableVariables incase of $ in strings
    Invoke-SQLCmd -Server "$SQLHost" -Database $Database -Query $Query -DisableVariables -ErrorAction Stop
}

Function Truncate-Table {
    param([String]$Table)

    $TruncCM = "
        TRUNCATE TABLE $Table;
    "
    Exec-SQL -Query $TruncCM
}

Function Channel-List {
    $c = "SELECT DISTINCT ID FROM dbo.Channel WHERE ID <> '$UnknownValue';"
    return $(Exec-SQL -Query $c).ID
}

Function Member-List {
    $m = "SELECT DISTINCT ID FROM [dbo].[Member] WHERE ID <> '$UnknownValue';"
    return $(Exec-SQL -Query $m).ID
}

Function Get-MaxProcessDate {
    $getDate = "SELECT TOP 1 EpochTimeStamp as [MaxDate] FROM dbo.ProcessMessageLog ORDER BY RID DESC;"
    return  $(Exec-SQL -Query $getDate).MaxDate
}

Function Sanitize-String {
    param([String]$Str)
    return ($Str.replace("'","''"))
}


################# MAIN ###############
Function Main {
    Load-UserList
    Load-ChannelList
    Load-UserGroups
    Load-Stars-ByUser
    If($Reprocess) {
        Load-Messages-Reactions -Full
    }
    Else {
        Load-Messages-Reactions
    }
}


Main