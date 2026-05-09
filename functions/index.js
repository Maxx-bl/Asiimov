const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();

exports.sendNotificationOnMessage = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    const messageData = event.data.data();

    if (!messageData) {
      console.log("No message data found.");
      return;
    }

    const senderID = messageData.senderID;
    const receiverID = messageData.receiverID;

    // Get receiver's FCM token
    const receiverDoc = await db.collection("users").doc(receiverID).get();
    if (!receiverDoc.exists) {
      console.log("Receiver user not found.");
      return;
    }

    const receiverData = receiverDoc.data();
    const fcmToken = receiverData.fcmToken;

    if (!fcmToken) {
      console.log("Receiver has no FCM token.");
      return;
    }

    // Get sender's username
    const senderDoc = await db.collection("users").doc(senderID).get();
    const senderData = senderDoc.exists ? senderDoc.data() : {};
    const senderUsername = senderData.username || "Someone";

    // Build notification payload
    const notification = {
      token: fcmToken,
      notification: {
        title: senderUsername,
        body: "New message",
      },
      data: {
        senderID: senderID,
        senderUsername: senderUsername,
        type: "chat_message",
      },
      android: {
        notification: {
          channelId: "chat_messages",
          priority: "high",
          defaultSound: true,
        },
      },
    };

    try {
      await getMessaging().send(notification);
      console.log(`Notification sent to ${receiverID} from ${senderUsername}`);
    } catch (error) {
      console.error("Error sending notification:", error);
      // If token is invalid, remove it
      if (
        error.code === "messaging/invalid-registration-token" ||
        error.code === "messaging/registration-token-not-registered"
      ) {
        await db.collection("users").doc(receiverID).update({
          fcmToken: null,
        });
        console.log("Removed invalid FCM token for user:", receiverID);
      }
    }
  }
);
