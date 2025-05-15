console.log("Login screen loaded");

import Feather from "@expo/vector-icons/Feather";
import { useRouter } from "expo-router";
import { signInWithEmailAndPassword } from "firebase/auth";
import React, { useState } from "react";
import {
  Alert,
  SafeAreaView,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from "react-native";
import colors from "../../constants/Colors";
import { auth } from "../../constants/firebase";

export default function Login() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);

  const onHandleLogin = async () => {
    if (email !== "" && password !== "") {
      signInWithEmailAndPassword(auth, email, password).catch((err) =>
        Alert.alert("Login error", err.message)
      );
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.whiteSheet} />
      <SafeAreaView style={styles.form}>
        <Text style={styles.title}>Log In</Text>
        <TextInput
          style={styles.input}
          placeholder="Email"
          autoCapitalize="none"
          keyboardType="email-address"
          textContentType="emailAddress"
          autoFocus={true}
          value={email}
          onChangeText={(text) => setEmail(text)}
        />
        <View style={styles.passwordContainer}>
          <TextInput
            style={styles.passwordInput}
            placeholder="Password"
            autoCapitalize="none"
            autoCorrect={false}
            secureTextEntry={!showPassword}
            textContentType="password"
            value={password}
            onChangeText={(text) => setPassword(text)}
          />
          <TouchableOpacity
            style={styles.toggleButton}
            onPress={() => setShowPassword(!showPassword)}
          >
            <Text style={styles.toggleButtonText}>
              {showPassword ? (
                <Feather
                  name="eye-off"
                  size={24}
                  color={colors.gray}
                  style={{ marginRight: 10 }}
                />
              ) : (
                <Feather
                  name="eye"
                  size={24}
                  color={colors.gray}
                  style={{ marginRight: 10 }}
                />
              )}
            </Text>
          </TouchableOpacity>
        </View>
        <TouchableOpacity style={styles.button} onPress={onHandleLogin}>
          <Text
            style={{
              fontWeight: "bold",
              color: colors.background,
              fontSize: 18,
            }}
          >
            Go!
          </Text>
        </TouchableOpacity>
        <View
          style={{
            marginTop: 20,
            flexDirection: "row",
            alignItems: "center",
            alignSelf: "center",
          }}
        >
          <Text style={{ color: "gray", fontWeight: "600", fontSize: 14 }}>
            Don't have an account?{" "}
          </Text>
          <TouchableOpacity onPress={() => router.push("/auth/signup")}>
            <Text
              style={{ color: colors.primary, fontWeight: "600", fontSize: 14 }}
            >
              Sign Up
            </Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
      <StatusBar
        barStyle="light-content"
        translucent
        backgroundColor={colors.background}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  title: {
    fontSize: 36,
    fontWeight: "bold",
    color: colors.primary,
    alignSelf: "center",
    paddingBottom: 24,
  },
  input: {
    backgroundColor: colors.mediumGray,
    height: 58,
    marginBottom: 20,
    fontSize: 16,
    borderRadius: 10,
    padding: 12,
  },
  passwordContainer: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: colors.mediumGray,
    height: 58,
    marginBottom: 20,
    borderRadius: 10,
  },
  passwordInput: {
    flex: 1,
    fontSize: 16,
    padding: 12,
  },
  toggleButton: {
    paddingHorizontal: 12,
  },
  toggleButtonText: {
    fontWeight: "600",
    fontSize: 14,
  },
  whiteSheet: {
    width: "100%",
    height: "75%",
    position: "absolute",
    bottom: 0,
    backgroundColor: colors.background,
    borderTopLeftRadius: 60,
  },
  form: {
    flex: 1,
    justifyContent: "center",
    marginHorizontal: 30,
  },
  button: {
    backgroundColor: colors.primary,
    height: 58,
    borderRadius: 10,
    justifyContent: "center",
    alignItems: "center",
    marginTop: 40,
  },
});
