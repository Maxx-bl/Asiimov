import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  //instance
  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  //get current user
  User? getCurrentUser() {
    return auth.currentUser;
  }

  //signin
  Future<UserCredential> signInWithEmailAndPassword(
      String email, password) async {
    try {
      UserCredential userCredential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'invalid-email':
          throw Exception('invalid-email');
        case 'user-disabled':
          throw Exception('user-disabled');
        case 'user-not-found':
          throw Exception('user-not-found');
        case 'wrong-password':
          throw Exception('wrong-password');
        default:
          throw Exception('unknown-error');
      }
    }
  }

  //signup
  Future<UserCredential> signUpWithEmailAndPassword(
      String email, password, username) async {
    try {
      //username already exists?
      final usernameQuery = await firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .get();

      if (usernameQuery.docs.isNotEmpty) {
        throw Exception('username-already-in-use');
      }

      UserCredential userCredential = await auth.createUserWithEmailAndPassword(
          email: email, password: password);

      await userCredential.user!.updateProfile(
        displayName: username,
        photoURL:
            'https://avatar.iran.liara.run/username?username=${username.toLowerCase()}',
      );

      await firestore.collection('users').doc(userCredential.user!.uid).set({
        'uid': userCredential.user!.uid,
        'email': email,
        'username': username,
      });

      return userCredential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw Exception('email-already-in-use');
      }
      throw Exception(e.code);
    }
  }

  //signout
  Future<void> signOut() async {
    return await auth.signOut();
  }

  //errors
}
