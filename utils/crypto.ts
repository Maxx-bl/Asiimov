import CryptoJS from 'crypto-js';
import Config from "../settings.json";

const ENCRYPTION_KEY = Config.ENCRYPTION_KEY;

export const encryptMessage = (message: string): string => {
  return CryptoJS.AES.encrypt(message, ENCRYPTION_KEY).toString();
};

export const decryptMessage = (encrypted: string): string => {
  const bytes = CryptoJS.AES.decrypt(encrypted, ENCRYPTION_KEY);
  return bytes.toString(CryptoJS.enc.Utf8);
};
