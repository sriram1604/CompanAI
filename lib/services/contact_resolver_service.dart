import 'dart:developer' as developer;
import 'package:flutter_contacts/flutter_contacts.dart';

enum ContactResolutionStatus {
  singleMatch,
  ambiguousMatches,
  notFound,
  permissionDenied,
}

class ContactMatch {
  final Contact contact;
  final String displayName;
  final String? primaryPhoneNumber;
  final List<String> allPhoneNumbers;

  ContactMatch({
    required this.contact,
    required this.displayName,
    this.primaryPhoneNumber,
    required this.allPhoneNumbers,
  });

  Map<String, dynamic> toJson() => {
        'id': contact.id,
        'displayName': displayName,
        'primaryPhone': primaryPhoneNumber,
        'allPhones': allPhoneNumbers,
      };
}

class ContactResolutionResult {
  final ContactResolutionStatus status;
  final ContactMatch? primaryMatch;
  final List<ContactMatch> candidateMatches;
  final String query;
  final String message;

  ContactResolutionResult({
    required this.status,
    this.primaryMatch,
    this.candidateMatches = const [],
    required this.query,
    required this.message,
  });

  bool get isSingleMatch => status == ContactResolutionStatus.singleMatch;
  bool get isAmbiguous => status == ContactResolutionStatus.ambiguousMatches;
  bool get isNotFound => status == ContactResolutionStatus.notFound;
}

/// Native Android contact resolver that searches real device contacts.
/// Prevents the LLM from inventing or guessing phone numbers.
class ContactResolverService {
  static final ContactResolverService _instance = ContactResolverService._internal();
  factory ContactResolverService() => _instance;
  ContactResolverService._internal();

  /// Search contacts on device and resolve ambiguity
  Future<ContactResolutionResult> resolveContact(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return ContactResolutionResult(
        status: ContactResolutionStatus.notFound,
        query: query,
        message: 'No contact name specified.',
      );
    }

    // Direct phone number input (e.g. "+919876543210" or "9876543210")
    final digitsOnly = cleanQuery.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digitsOnly.length >= 7 && (cleanQuery.startsWith('+') || RegExp(r'^\d+$').hasMatch(cleanQuery))) {
      return ContactResolutionResult(
        status: ContactResolutionStatus.singleMatch,
        primaryMatch: ContactMatch(
          contact: Contact(displayName: cleanQuery),
          displayName: cleanQuery,
          primaryPhoneNumber: cleanQuery,
          allPhoneNumbers: [cleanQuery],
        ),
        query: query,
        message: 'Direct phone number: $cleanQuery',
      );
    }

    try {
      if (!await FlutterContacts.requestPermission()) {
        return ContactResolutionResult(
          status: ContactResolutionStatus.permissionDenied,
          query: query,
          message: 'Contact read permission is required to search contacts.',
        );
      }

      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      final lowerQuery = cleanQuery.toLowerCase();

      // 1. Exact match (case-insensitive)
      final exactMatches = <ContactMatch>[];
      // 2. StartsWith match
      final prefixMatches = <ContactMatch>[];
      // 3. Word contains match
      final wordMatches = <ContactMatch>[];
      // 4. Substring contains match
      final substringMatches = <ContactMatch>[];

      for (final c in contacts) {
        final name = c.displayName.trim();
        final lowerName = name.toLowerCase();
        if (lowerName.isEmpty) continue;

        final phones = c.phones.map((p) => p.number.replaceAll(RegExp(r'\s+'), '')).where((n) => n.isNotEmpty).toList();
        final primaryPhone = phones.isNotEmpty ? phones.first : null;

        final match = ContactMatch(
          contact: c,
          displayName: name,
          primaryPhoneNumber: primaryPhone,
          allPhoneNumbers: phones,
        );

        if (lowerName == lowerQuery) {
          exactMatches.add(match);
        } else if (lowerName.startsWith(lowerQuery)) {
          prefixMatches.add(match);
        } else {
          final words = lowerName.split(RegExp(r'\s+'));
          if (words.any((w) => w == lowerQuery || w.startsWith(lowerQuery))) {
            wordMatches.add(match);
          } else if (lowerName.contains(lowerQuery)) {
            substringMatches.add(match);
          }
        }
      }

      // Prioritize matches
      final candidates = exactMatches.isNotEmpty
          ? exactMatches
          : (prefixMatches.isNotEmpty
              ? prefixMatches
              : (wordMatches.isNotEmpty ? wordMatches : substringMatches));

      if (candidates.isEmpty) {
        return ContactResolutionResult(
          status: ContactResolutionStatus.notFound,
          query: query,
          message: 'No contact found matching "$query" in phonebook.',
        );
      }

      if (candidates.length == 1) {
        final single = candidates.first;
        if (single.primaryPhoneNumber == null || single.primaryPhoneNumber!.isEmpty) {
          return ContactResolutionResult(
            status: ContactResolutionStatus.notFound,
            primaryMatch: single,
            query: query,
            message: 'Found contact "${single.displayName}", but no phone number is saved for them.',
          );
        }

        return ContactResolutionResult(
          status: ContactResolutionStatus.singleMatch,
          primaryMatch: single,
          candidateMatches: candidates,
          query: query,
          message: 'Found "${single.displayName}" (${single.primaryPhoneNumber})',
        );
      }

      // Multiple ambiguous matches found (e.g. "Amma Mobile", "Amma Home")
      return ContactResolutionResult(
        status: ContactResolutionStatus.ambiguousMatches,
        primaryMatch: candidates.first,
        candidateMatches: candidates,
        query: query,
        message: 'Found ${candidates.length} contacts matching "$query". Please choose one.',
      );
    } catch (e) {
      developer.log('Contact resolution error: $e', name: 'ContactResolverService');
      return ContactResolutionResult(
        status: ContactResolutionStatus.notFound,
        query: query,
        message: 'Error searching contacts: $e',
      );
    }
  }
}
