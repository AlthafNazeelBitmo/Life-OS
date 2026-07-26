import '../../core/error/result.dart';
import '../entities/person.dart';

abstract interface class PeopleRepository {
  Stream<List<Person>> watchPeople();

  Stream<Person?> watchPerson(String id);

  Stream<List<Interaction>> watchInteractions(String personId);

  Future<Result<Person>> upsert(Person person);

  Future<Result<void>> delete(String id);

  Future<Result<Interaction>> logInteraction(Interaction interaction);

  /// People whose follow-up window has elapsed, most overdue first.
  Future<Result<List<Person>>> needingFollowUp();

  Future<Result<List<Person>>> birthdaysWithin(int days);

  /// Resolves names the AI extracted from a journal entry to existing people,
  /// creating none — matching is the caller's decision to confirm.
  Future<Result<List<Person>>> matchNames(List<String> names);
}
