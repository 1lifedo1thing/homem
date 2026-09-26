# Homem privacy policy

Last updated: September 26, 2026.

This policy describes how the Homem client handles your information. The servers and services you choose have their own policies, as explained below.

## About Homem

Homem, provided by Kitta Ltd, is an independent client for the official Memoh service and compatible third-party or self-hosted Memoh servers.

## Connecting to a server

When you sign in, Homem sends the information needed to authenticate to the service you select. Official Memoh sign-in uses your email and verification code, or the official website's sign-in flow. A custom server receives the username and password or access token you provide. Connected services can receive your network address and request information as part of normal communication.

Signing in does not grant permission to share content with AI services. After sign-in, Homem reads the server's provider configuration to identify recipients and presents a separate AI data-sharing disclosure. Authentication and configuration requests contain the session credentials needed to communicate with your chosen server, but the disclosure does not send conversation content to AI services.

## AI services: data, recipients, and purpose

With your permission, your selected server receives the messages you enter, conversation history, files and photos you attach or upload, voice recordings, agent instructions, memories, and tool inputs and results. This information may include personal information that you or others include in the content. Terminal input and desktop-control events are sent to your remote workspace; files and tool results in that workspace may also become context for an agent.

Your server may forward the content needed for a request to its configured AI model, memory, search, fetch, speech, transcription, and video service providers. These services use that content to generate responses, remember or retrieve information, search or fetch requested resources, process media, and perform the actions you request. Agent tools and integrations you or your server administrator configure can also receive the information needed for their actions.

Homem does not select a single AI provider on behalf of all users. The in-app disclosure identifies your selected server's address and the enabled service names and endpoint hosts reported by that server. For example, a server can configure OpenAI, Anthropic, Google, another provider, or a private gateway; these examples do not mean that all of them receive your data. A gateway may forward requests to a downstream provider chosen by the server administrator. Ask that administrator about downstream recipients before allowing sharing if the gateway's routing is not clear to you. Servers added through the custom-server option, including a server supplied for app review, are treated as user-operated servers and receive the same disclosure and consent checks.

## Permission and withdrawal

Before connected workspace features are available, Homem asks you to choose **Allow and continue** or **Don't allow**. The disclosure describes the data, purpose, and recipients and links to this policy. Declining disconnects without sending content to AI services; you can still use the local demo. Existing accounts must also give permission after upgrading to the version that introduces this disclosure.

Permission is stored on your device for the selected account, workspace, disclosure version, and recipient configuration. Homem checks the server's provider configuration before new content-sharing operations. If the reported recipients change, permission is required again. If the app cannot read that configuration, sharing remains blocked. The iOS share extension applies the same permission checks before creating an upload folder or uploading files.

To withdraw permission, open **Settings → AI data sharing → Withdraw permission and disconnect**. Withdrawal stops new sharing through that connection in Homem and its share extension. It does not delete information already transmitted, cancel work already running on the server, or change server-side schedules. Use the server's controls to stop those tasks or delete information already stored.

## Protection, retention, and deletion

Third-party services processing personal data for use with Homem must provide the same or equal protection described in this policy: use data only for the disclosed and authorized purposes; protect it against unauthorized access; limit retention to what is needed for those purposes or required by law; and provide a way to request deletion. We require these protections from any processor we engage for Homem. User-operated server administrators are responsible for selecting and configuring their providers to meet these requirements, including any downstream services used by a gateway.

Homem does not control or independently verify a user-operated server's provider contracts, retention periods, or model-training settings. Consent in Homem does not change those settings or grant a provider permission to train on your content. Consult your server operator and the identified providers' policies before sharing; do not allow sharing if their protections do not meet your requirements. Request deletion of server and provider copies using the server's account controls or by contacting its operator. Kitta does not receive a separate copy of your connected content merely because you use Homem.

Use HTTPS to protect traffic to your server; custom HTTP connections are unencrypted and are identified in the app. The client does not forward authentication credentials to arbitrary redirect destinations.

## Information on your device

Homem stores saved account credentials, sessions, and data-sharing permission receipts in the device Keychain. It does not persist custom-server passwords. Account details, workspace layouts, and display preferences are stored locally, and conversation drafts are saved locally in the Keychain. Permission receipts identify the consent scope and configuration without storing provider API keys or content. The client also uses temporary files and caches to display or share content. Removing a saved account removes its locally saved credentials and drafts; this does not delete the server account or server-side data.

## Files, microphone, and remote workspaces

Files are sent when you choose to attach or upload them. Microphone access is requested when you record a voice message. Recordings can be attached to a conversation and sent to the selected server. Remote terminal input and desktop-control events are sent to your workspace. Desktop view-only mode blocks remote mouse and keyboard input from Homem.

The app does not capture the device camera for remote desktop viewing. Local read-aloud uses Apple's speech synthesis. Demo mode uses local sample content and does not contact a Memoh server.

## Tracking and analytics

The native Homem client does not include advertising, cross-app tracking, or an analytics SDK. This does not describe the independent policies of the Memoh service, a custom server, an identity provider used during browser sign-in, or third-party integrations configured on your server.

## Your choices

You can disconnect or remove saved accounts, choose a different server, and manage microphone permission in iOS Settings. Use the selected server's account controls or contact its operator to request deletion of server-side information. Prefer HTTPS when connecting to a custom server; unencrypted HTTP connections are identified in the app.

## Contact

For questions about Homem or this policy, email [support@ieb.app](mailto:support@ieb.app). For information held by your selected Memoh server or integrations, contact that service’s operator. If you contact support, we receive the information you include and use it to respond to your request. Do not include passwords, tokens, verification codes, or private conversations.

## Sharing from other apps

When you choose Homem in the iOS share sheet, the extension temporarily copies the files you selected. You choose the account, workspace, and agent before saving. The extension reads your existing login from Homem’s Keychain access group, identifies configured recipients, and requires matching data-sharing permission before uploading. If permission has not been given or the recipient configuration changed, the extension presents the disclosure and asks for permission. You then explicitly choose Save to workspace. Temporary copies are removed when you finish or dismiss the extension; the server copies remain until deleted there. No files are uploaded merely by opening the share sheet.

## Changes

We will update this page when the client’s data practices change. The date above identifies the latest revision.
