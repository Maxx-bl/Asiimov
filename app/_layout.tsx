import {
  DarkTheme,
  DefaultTheme,
  ThemeProvider,
} from "@react-navigation/native";
import { useFonts } from "expo-font";
import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";
import "react-native-reanimated";

import { useColorScheme } from "@/hooks/useColorScheme";

import { onAuthStateChanged, User } from "firebase/auth";
import React, { createContext, useContext, useEffect, useState } from "react";
import { ActivityIndicator, View } from "react-native";
import { auth } from "../constants/firebase";

interface AuthUserContextType {
  user: User | null;
  setUser: React.Dispatch<React.SetStateAction<any>>;
}

const AuthUserContext = createContext<AuthUserContextType | undefined>(
  undefined
);

const AuthUserProvider = ({ children }: { children: any }) => {
  const [user, setUser] = useState<any>(null);
  return (
    <AuthUserContext.Provider value={{ user, setUser }}>
      {children}
    </AuthUserContext.Provider>
  );
};

function AuthStack() {
  return (
    <Stack screenOptions={{ headerShown: false }} initialRouteName="auth/login">
      <Stack.Screen name="auth/login" />
      <Stack.Screen name="auth/signup" />
    </Stack>
  );
}

function DefaultStack() {
  const colorScheme = useColorScheme();
  const [loaded] = useFonts({
    SpaceMono: require("../assets/fonts/SpaceMono-Regular.ttf"),
  });

  if (!loaded) {
    // Async font loading only occurs in development.
    return null;
  }
  return (
    <ThemeProvider value={colorScheme === "dark" ? DarkTheme : DefaultTheme}>
      <Stack>
        <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
        <Stack.Screen name="+not-found" />
      </Stack>
      <StatusBar style="auto" />
    </ThemeProvider>
  );
}

function RootNavigator() {
  const authContext = useContext(AuthUserContext);

  if (!authContext) {
    throw new Error("AuthUserContext must be used within an AuthUserProvider");
  }

  const { user, setUser } = authContext;
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (authenticatedUser) => {
      authenticatedUser ? setUser(authenticatedUser) : setUser(null);
      setLoading(false);
    });
    return () => unsubscribe();
  }, [setUser]);

  if (loading) {
    return (
      <View style={{ flex: 1, justifyContent: "center", alignItems: "center" }}>
        <ActivityIndicator size="large" />
      </View>
    );
  }

  return user ? <DefaultStack /> : <AuthStack />;
}

export default function RootLayout() {
  return (
    <AuthUserProvider>
      <RootNavigator />
    </AuthUserProvider>
  );
}
