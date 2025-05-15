import Feather from "@expo/vector-icons/Feather";
import DateTimePicker from "@react-native-community/datetimepicker";
import { useRouter } from "expo-router";
import {
  createUserWithEmailAndPassword,
  reload,
  updateProfile,
} from "firebase/auth";
import {
  collection,
  doc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  where,
} from "firebase/firestore";
import moment from "moment";
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
import { auth, db } from "../../constants/firebase";

export default function Signup() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [passwordConfirm, setPasswordConfirm] = useState("");
  const [dateOfBirth, setDateOfBirth] = useState<Date | null>(null);
  const [isDatePickerVisible, setDatePickerVisibility] = useState(false);
  const [username, setUsername] = useState("");
  const [errorMsg, setErrorMsg] = useState("");

  const showDatePicker = () => {
    setDatePickerVisibility(true);
  };

  const hideDatePicker = () => {
    setDatePickerVisibility(false);
  };

  const onHandleSignup = async () => {
    if (email !== "" && password !== "" && username !== "" && dateOfBirth) {
      if (password !== passwordConfirm) {
        setErrorMsg("Passwords do not match!");
        setTimeout(() => {
          setErrorMsg("");
        }, 3000);
        return;
      }

      const MinLength = 3;
      const MaxLength = 25;
      if (username.length < MinLength) {
        setErrorMsg(`Username must be at least ${MinLength} characters long!`);
        setTimeout(() => {
          setErrorMsg("");
        }, 3000);
        return;
      }
      if (username.length > MaxLength) {
        setErrorMsg(`Username must be less than ${MaxLength} characters long!`);
        setTimeout(() => {
          setErrorMsg("");
        }, 3000);
        return;
      }

      if (!moment().subtract(18, "years").isAfter(dateOfBirth)) {
        setErrorMsg("You must be at least 18 years old to sign up.");
        setTimeout(() => setErrorMsg(""), 3000);
        return;
      }

      const AuthorizedCharacters = "abcdefghijklmnopqrstuvwxyz1234567890_-.";
      let check = true;
      let i = 0;
      while (check && i < username.length) {
        if (AuthorizedCharacters.indexOf(username[i].toLowerCase()) < 0)
          check = false;
        i++;
      }
      if (!check) {
        setErrorMsg("You can only use letters, numbers or . - _");
        setTimeout(() => {
          setErrorMsg("");
        }, 5000);
        return;
      }

      const userReference = collection(db, "users");
      const q = query(
        userReference,
        where("username", "==", username.toLowerCase())
      );
      const snapshot = await getDocs(q);
      if (!snapshot.empty) {
        setErrorMsg("Username already taken!");
        setTimeout(() => {
          setErrorMsg("");
        }, 3000);
      } else {
        setErrorMsg("");
        createUserWithEmailAndPassword(auth, email, password)
          .then(async ({ user }) => {
            await updateProfile(user, {
              displayName: username.toLowerCase(),
              photoURL: `https://avatar.iran.liara.run/username?username=${username.toLowerCase()}`,
            });
            await reload(user);
            const userReference = collection(db, "users");
            await setDoc(doc(userReference, user.uid), {
              uid: user.uid,
              email: user.email,
              username: username.toLowerCase(),
              avatar: `https://avatar.iran.liara.run/username?username=${username.toLowerCase()}`,
              createdAt: serverTimestamp(),
            });
          })
          .catch((err) => Alert.alert("Signup error", err.message));
      }
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.whiteSheet} />
      <SafeAreaView style={styles.form}>
        <Text style={styles.title}>Sign Up</Text>
        <TextInput
          style={styles.input}
          placeholder="Email"
          autoCapitalize="none"
          keyboardType="email-address"
          textContentType="emailAddress"
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
        <TextInput
          style={styles.input}
          placeholder="Confirm password"
          autoCapitalize="none"
          autoCorrect={false}
          secureTextEntry={!showPassword}
          textContentType="password"
          value={passwordConfirm}
          onChangeText={(text) => setPasswordConfirm(text)}
        />
        <TouchableOpacity
          style={styles.datePickerContainer}
          onPress={() => showDatePicker()}
        >
          <Text style={styles.datePickerText}>
            {dateOfBirth
              ? moment(dateOfBirth).format("DD MMMM YYYY")
              : "Date of Birth"}
          </Text>
        </TouchableOpacity>
        {isDatePickerVisible && (
          <DateTimePicker
            value={dateOfBirth || new Date(2000, 0, 1)}
            mode="date"
            display="calendar"
            onChange={(event, selectedDate) => {
              if (event.type === "set") {
                setDateOfBirth(selectedDate || dateOfBirth);
              }
              hideDatePicker();
            }}
            maximumDate={new Date()}
          />
        )}
        <TextInput
          style={styles.input}
          placeholder="Username"
          autoCapitalize="none"
          textContentType="username"
          value={username}
          onChangeText={(text) => setUsername(text)}
        />
        {errorMsg ? <Text style={styles.error}>{errorMsg}</Text> : null}
        <TouchableOpacity style={styles.button} onPress={onHandleSignup}>
          <Text
            style={{
              fontWeight: "bold",
              color: colors.background,
              fontSize: 18,
            }}
          >
            Start!
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
            Already have an account?{" "}
          </Text>
          <TouchableOpacity onPress={() => router.push("/auth/login")}>
            <Text
              style={{ color: colors.primary, fontWeight: "600", fontSize: 14 }}
            >
              Log In
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
  error: {
    color: "red",
    fontSize: 16,
    marginBottom: 10,
    alignSelf: "center",
  },
  datePickerContainer: {
    backgroundColor: colors.mediumGray,
    height: 58,
    marginBottom: 20,
    justifyContent: "center",
    borderRadius: 10,
    paddingHorizontal: 12,
  },
  datePickerText: {
    fontSize: 16,
    color: "#999999",
  },
});
