# Slack Notifications

## Cluster Expiration Notifications

The automated cleanup job (`infra-cleanup-expired-clusters.yaml`) sends two kinds of Slack notification,
through the shared [notify-slack](https://github.com/Apicurio/apicurio-github-actions/tree/main/notify-slack) action:

- **Expiring soon** (less than 20% of a cluster's lifetime left) goes to the important channel and @mentions
  the user who created the cluster, so they can extend or save their work. When several users' clusters
  are expiring, the first one with a Slack mapping is mentioned and the rest are named in the text.
- **Could not be destroyed** (expired, but destroying it failed) goes to the important channel and @mentions
  the creator in the same way: the cluster keeps running, and costing money, until someone cleans it up.
  It is reported once; the job keeps retrying every hour.

A cluster that is destroyed as planned sends nothing: its creator was warned before it expired.

For the @mention to work, your GitHub username must be mapped to your Slack member ID in the `SLACK_USER_MAP`
organization secret. If no mapping is found, the notification names your GitHub username instead.

## How to Add Your Slack Member ID

1. Open Slack (desktop or web).
2. Click your **profile picture** in the top-right corner.
3. Click **"Profile"**.
4. Click the **three dots (...)** menu button.
5. Select **"Copy member ID"**.
6. Ask an organization admin to add your GitHub username and Slack member ID to the `SLACK_USER_MAP`
   organization secret, a JSON object such as `{"your-github-username": "YOUR_SLACK_MEMBER_ID"}`.
