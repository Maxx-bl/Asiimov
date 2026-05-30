const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const disposableDomainsSet = new Set(require("disposable-email-domains"));

initializeApp();

const db = getFirestore();

function prefAllowed(prefs, type) {
  const prefMap = {
    chat_message: "messages",
    post_share: "messages",
    follow: "followers",
    follow_request: "followers",
    follow_accept: "followers",
    comment: "comments",
  };
  const key = prefMap[type];
  return !(key && prefs[key] === false);
}

async function deliverNotification(userId, title, body, data, androidTag) {
  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) {
    console.warn(`deliverNotification: user ${userId} not found`);
    return;
  }

  const userData = userDoc.data();
  const fcmToken = userData.fcmToken;
  if (!fcmToken) {
    console.warn(`deliverNotification: no FCM token for user ${userId}`);
    return;
  }

  const prefs = userData.notificationPrefs || {};
  if (!prefAllowed(prefs, data.type)) {
    console.log(`deliverNotification: blocked by prefs for user ${userId}, type=${data.type}`);
    return;
  }

  const truncatedBody =
    body.length > 200 ? body.substring(0, 200) + "..." : body;

  const message = {
    token: fcmToken,
    notification: { title, body: truncatedBody },
    data,
    android: {
      notification: {
        channelId: "chat_messages",
        priority: "high",
        color: "#A8C4D8",
        ...(androidTag ? { tag: androidTag } : {}),
      },
    },
  };

  try {
    await getMessaging().send(message);
  } catch (err) {
    if (
      err.code === "messaging/invalid-registration-token" ||
      err.code === "messaging/registration-token-not-registered"
    ) {
      console.warn(`deliverNotification: stale token for user ${userId}, clearing`);
      await db.collection("users").doc(userId).update({ fcmToken: null });
    } else {
      console.error(`deliverNotification: FCM send failed for user ${userId}`, err.code, err.message);
    }
  }
}

// Firestore trigger: fires on every new chat message
exports.onNewMessage = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    const msg = event.data.data();
    const { chatId } = event.params;

    if (!msg || msg.isSystemMessage === true) return;

    const senderID = msg.senderID;
    const senderUsername = msg.senderUsername || "Someone";
    const notifBody = msg.notifBody || "New message";

    const chatDoc = await db.collection("chats").doc(chatId).get();
    const chatData = chatDoc.exists ? chatDoc.data() : {};
    const isGroup = chatData.type === "group";

    if (isGroup) {
      const members = chatData.members || [];
      const mutedBy = chatData.mutedBy || [];
      const groupName = chatData.groupName || "Group";
      const creatorId = chatData.creatorId || "";
      const mentionedIds = Array.isArray(msg.mentionedIds) ? msg.mentionedIds : [];

      // Members muted the group but are mentioned still receive a notification
      // (unless they disabled message notifications globally — deliverNotification handles that)
      const recipients = members.filter(
        (id) => id !== senderID && (!mutedBy.includes(id) || mentionedIds.includes(id))
      );

      // Send all group notifications in parallel — avoids sequential timeouts
      await Promise.allSettled(
        recipients.map((memberId) =>
          deliverNotification(
            memberId,
            groupName,
            `${senderUsername}: ${notifBody}`,
            {
              senderID,
              senderUsername,
              type: "chat_message",
              isGroup: "true",
              groupId: chatId,
              groupName,
              creatorId,
            },
            chatId
          )
        )
      );
    } else {
      const receiverID = msg.receiverID;
      if (!receiverID) return;
      await deliverNotification(
        receiverID,
        senderUsername,
        notifBody,
        { senderID, senderUsername, type: "chat_message" },
        senderID
      );
    }
  }
);

// Callable: validates that an email is not from a disposable provider
exports.validateEmail = onCall((request) => {
  const { email } = request.data;
  if (!email || typeof email !== "string") {
    throw new HttpsError("invalid-argument", "Email is required");
  }
  const parts = email.split("@");
  if (parts.length !== 2 || !parts[1]) {
    throw new HttpsError("invalid-argument", "Invalid email format");
  }
  const domain = parts[1].toLowerCase();
  if (disposableDomainsSet.has(domain)) {
    throw new HttpsError("invalid-argument", "disposable-email");
  }
  return { valid: true };
});

// Callable: for follows, comments, reactions, support
exports.sendNotification = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const { receiverID, message, title, type, extraData, androidTag } = request.data;
  if (!receiverID || !message) return;

  const rawData = {
    senderID: request.auth.uid,
    type: type || "notification",
    ...(extraData || {}),
  };

  const data = {};
  for (const [k, v] of Object.entries(rawData)) {
    data[k] = String(v);
  }

  await deliverNotification(receiverID, title || "Notification", message, data, androidTag || null);
});
