import json
import time
import os
import boto3
import requests

# Initialize resources and environment variables
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DDB_TABLE'])

SLACK_URL = os.environ['SLACK_WEBHOOK_URL']
THRESHOLD = int(os.environ.get("ALERT_THRESHOLD", 5))
WINDOW_SECONDS = int(os.environ.get("ALERT_WINDOW_SECONDS", 300))

def lambda_handler(event, context):
    try:
        # Handle both direct payloads (e.g., curl) and API Gateway events
        if 'body' in event:
            body = json.loads(event['body'])
        else:
            body = event

        # Only proceed if it's a user removal from a group
        if body.get("eventType") != "group.user_membership.remove":
            return {"statusCode": 200, "body": "Ignored"}

        # Extract group name from the payload
        group_info = next((t for t in body["target"] if t["type"] == "UserGroup"), None)
        if not group_info:
            return {"statusCode": 400, "body": "Missing group information"}

        group_name = group_info["displayName"]
        timestamp = int(time.time())
        ttl = timestamp + WINDOW_SECONDS

        # Save the event to DynamoDB
        table.put_item(Item={
            "group_name": group_name,
            "timestamp": timestamp,
            "ttl": ttl
        })

        # Query for recent removals from the same group
        response = table.query(
            KeyConditionExpression="group_name = :g AND timestamp >= :start",
            ExpressionAttributeValues={
                ":g": group_name,
                ":start": timestamp - WINDOW_SECONDS
            }
        )

        # Alert to Slack if the number of removals exceeds the threshold
        if len(response['Items']) > THRESHOLD:
            msg = f":warning: *{len(response['Items'])}* users removed from *{group_name}* in the last 5 minutes!"
            requests.post(SLACK_URL, json={"text": msg})

        return {"statusCode": 200, "body": "Processed"}

    except Exception as e:
        print("Error:", str(e))
        return {
            "statusCode": 500,
            "body": json.dumps({"message": "Internal Server Error", "error": str(e)})
        }
