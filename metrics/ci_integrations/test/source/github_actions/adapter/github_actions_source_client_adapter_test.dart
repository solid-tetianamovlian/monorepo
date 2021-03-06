// Use of this source code is governed by the Apache License, Version 2.0
// that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ci_integration/client/github_actions/models/github_action_conclusion.dart';
import 'package:ci_integration/client/github_actions/models/github_action_status.dart';
import 'package:ci_integration/client/github_actions/models/workflow_run.dart';
import 'package:ci_integration/client/github_actions/models/workflow_run_artifact.dart';
import 'package:ci_integration/client/github_actions/models/workflow_run_artifacts_page.dart';
import 'package:ci_integration/client/github_actions/models/workflow_run_job.dart';
import 'package:ci_integration/client/github_actions/models/workflow_run_jobs_page.dart';
import 'package:ci_integration/client/github_actions/models/workflow_runs_page.dart';
import 'package:ci_integration/source/github_actions/adapter/github_actions_source_client_adapter.dart';
import 'package:ci_integration/util/archive/archive_helper.dart';
import 'package:ci_integration/util/model/interaction_result.dart';
import 'package:metrics_core/metrics_core.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../../test_utils/extensions/interaction_result_answer.dart';
import '../../../test_utils/matchers.dart';
import '../test_utils/github_actions_client_mock.dart';
import '../test_utils/test_data/github_actions_test_data_generator.dart';

// ignore_for_file: avoid_redundant_argument_values

void main() {
  group("GithubActionsSourceClientAdapter", () {
    const jobName = 'job';
    const fetchLimit = 28;
    const buildNumber = 1;
    final testData = GithubActionsTestDataGenerator(
      workflowIdentifier: 'workflow',
      jobName: jobName,
      coverageArtifactName: 'coverage-summary.json',
      coverage: Percent(0.6),
      url: 'url',
      startDateTime: DateTime(2020),
      completeDateTime: DateTime(2021),
      duration: DateTime(2021).difference(DateTime(2020)),
    );

    final archiveHelperMock = _ArchiveHelperMock();
    final archiveMock = _ArchiveMock();
    final githubActionsClientMock = GithubActionsClientMock();
    final adapter = GithubActionsSourceClientAdapter(
      githubActionsClient: githubActionsClientMock,
      archiveHelper: archiveHelperMock,
      workflowIdentifier: testData.workflowIdentifier,
      coverageArtifactName: testData.coverageArtifactName,
    );

    final coverageJson = <String, dynamic>{'pct': 0.6};
    final coverageBytes = utf8.encode(jsonEncode(coverageJson)) as Uint8List;

    final emptyWorkflowRunJobsPage = WorkflowRunJobsPage(
      page: 1,
      nextPageUrl: testData.url,
      values: const [],
    );
    final defaultRunsPage = WorkflowRunsPage(
      values: testData.generateWorkflowRunsByNumbers(
        runNumbers: [2, 1],
      ),
    );
    final defaultJobsPage = WorkflowRunJobsPage(
      values: [testData.generateWorkflowRunJob()],
    );
    final defaultArtifactsPage = WorkflowRunArtifactsPage(values: [
      WorkflowRunArtifact(name: testData.coverageArtifactName),
    ]);
    final defaultBuildData = testData.generateBuildDataByNumbers(
      buildNumbers: [2, 1],
    );
    final defaultBuild = testData.generateBuildData();
    const defaultWorkflowRun = WorkflowRun();

    final artifactsPage = WorkflowRunArtifactsPage(
      values: const [WorkflowRunArtifact()],
      nextPageUrl: testData.url,
    );

    PostExpectation<Uint8List> whenDecodeCoverage({
      Uint8List withArtifactBytes,
    }) {
      when(githubActionsClientMock.downloadRunArtifactZip(any))
          .thenSuccessWith(withArtifactBytes);

      when(archiveHelperMock.decodeArchive(withArtifactBytes))
          .thenReturn(archiveMock);

      return when(
        archiveHelperMock.getFileContent(archiveMock, 'coverage-summary.json'),
      );
    }

    PostExpectation<Future<InteractionResult<WorkflowRunArtifactsPage>>>
        whenFetchCoverage({
      WorkflowRun withWorkflowRun,
    }) {
      when(githubActionsClientMock.fetchWorkflowRunByUrl(any))
          .thenSuccessWith(withWorkflowRun);

      return when(githubActionsClientMock.fetchRunArtifacts(
        any,
        perPage: anyNamed('perPage'),
        page: anyNamed('page'),
      ));
    }

    PostExpectation<Future<InteractionResult<WorkflowRunsPage>>>
        whenFetchWorkflowRuns({
      WorkflowRunJobsPage withJobsPage,
    }) {
      when(githubActionsClientMock.fetchRunJobs(
        any,
        status: anyNamed('status'),
        perPage: anyNamed('perPage'),
        page: anyNamed('page'),
      )).thenSuccessWith(withJobsPage);

      return when(
        githubActionsClientMock.fetchWorkflowRuns(
          any,
          status: anyNamed('status'),
          perPage: anyNamed('perPage'),
          page: anyNamed('page'),
        ),
      );
    }

    setUp(() {
      reset(githubActionsClientMock);
      reset(archiveHelperMock);
    });

    test(
      "throws an ArgumentError if the given Github Actions client is null",
      () {
        expect(
          () => GithubActionsSourceClientAdapter(
            githubActionsClient: null,
            archiveHelper: archiveHelperMock,
            workflowIdentifier: testData.workflowIdentifier,
            coverageArtifactName: testData.coverageArtifactName,
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      "throws an ArgumentError if the given archive helper is null",
      () {
        expect(
          () => GithubActionsSourceClientAdapter(
            githubActionsClient: githubActionsClientMock,
            archiveHelper: null,
            workflowIdentifier: testData.workflowIdentifier,
            coverageArtifactName: testData.coverageArtifactName,
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      "throws an ArgumentError if the given workflow identifier is null",
      () {
        expect(
          () => GithubActionsSourceClientAdapter(
            githubActionsClient: githubActionsClientMock,
            archiveHelper: archiveHelperMock,
            workflowIdentifier: null,
            coverageArtifactName: testData.coverageArtifactName,
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      "throws an ArgumentError if the given coverage artifact name is null",
      () {
        expect(
          () => GithubActionsSourceClientAdapter(
            githubActionsClient: githubActionsClientMock,
            archiveHelper: archiveHelperMock,
            workflowIdentifier: testData.workflowIdentifier,
            coverageArtifactName: null,
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      "creates an instance with the given parameters",
      () {
        final adapter = GithubActionsSourceClientAdapter(
          githubActionsClient: githubActionsClientMock,
          archiveHelper: archiveHelperMock,
          workflowIdentifier: testData.workflowIdentifier,
          coverageArtifactName: testData.coverageArtifactName,
        );

        expect(adapter.githubActionsClient, equals(githubActionsClientMock));
        expect(adapter.archiveHelper, equals(archiveHelperMock));
        expect(
          adapter.workflowIdentifier,
          equals(testData.workflowIdentifier),
        );
        expect(
          adapter.coverageArtifactName,
          equals(testData.coverageArtifactName),
        );
      },
    );

    test(
      ".fetchBuilds() throws an ArgumentError if the given fetch limit is 0",
      () {
        expect(
          () => adapter.fetchBuilds(jobName, 0),
          throwsArgumentError,
        );
      },
    );

    test(
      ".fetchBuilds() throws an ArgumentError if the given fetch limit is a negative number",
      () {
        expect(
          () => adapter.fetchBuilds(jobName, -1),
          throwsArgumentError,
        );
      },
    );

    test(".fetchBuilds() fetches builds", () {
      whenFetchWorkflowRuns(withJobsPage: defaultJobsPage)
          .thenSuccessWith(defaultRunsPage);

      final result = adapter.fetchBuilds(jobName, fetchLimit);

      expect(result, completion(equals(defaultBuildData)));
    });

    test(
      ".fetchBuilds() returns no more than the given fetch limit number of builds",
      () {
        const fetchLimit = 12;
        final workflowRuns = testData.generateWorkflowRunsByNumbers(
          runNumbers: List.generate(30, (index) => index),
        );

        final workflowRunsPage = WorkflowRunsPage(values: workflowRuns);

        whenFetchWorkflowRuns(withJobsPage: defaultJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final result = adapter.fetchBuilds(jobName, fetchLimit);

        expect(
          result,
          completion(
            hasLength(lessThanOrEqualTo(fetchLimit)),
          ),
        );
      },
    );

    test(
      ".fetchBuilds() returns an empty list if the client returns workflow runs with the queued status",
      () async {
        final queuedWorkflowRun = testData.generateWorkflowRun(
          status: GithubActionStatus.queued,
        );
        final workflowRunsPage = WorkflowRunsPage(
          values: [queuedWorkflowRun],
        );

        whenFetchWorkflowRuns(
          withJobsPage: defaultJobsPage,
        ).thenSuccessWith(workflowRunsPage);

        final result = await adapter.fetchBuilds(jobName, fetchLimit);

        expect(result, isEmpty);
      },
    );

    test(
      ".fetchBuilds() returns an empty list if the client returns workflow runs with the skipped conclusion",
      () async {
        final queuedWorkflowRun = testData.generateWorkflowRun(
          conclusion: GithubActionConclusion.skipped,
        );
        final workflowRunsPage = WorkflowRunsPage(
          values: [queuedWorkflowRun],
        );

        whenFetchWorkflowRuns(
          withJobsPage: defaultJobsPage,
        ).thenSuccessWith(workflowRunsPage);

        final result = await adapter.fetchBuilds(jobName, fetchLimit);

        expect(result, isEmpty);
      },
    );

    test(
      ".fetchBuilds() returns an empty list if the client returns workflow run jobs with the skipped conclusion",
      () {
        final skippedJob = testData.generateWorkflowRunJob(
          conclusion: GithubActionConclusion.skipped,
        );

        final workflowRunJobsPage = WorkflowRunJobsPage(values: [skippedJob]);

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(defaultRunsPage);

        final result = adapter.fetchBuilds(jobName, fetchLimit);

        expect(result, completion(isEmpty));
      },
    );

    test(
      ".fetchBuilds() returns an empty list if the client returns workflow run jobs with the queued status",
      () async {
        final queuedJob = testData.generateWorkflowRunJob(
          status: GithubActionStatus.queued,
        );

        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [queuedJob],
        );

        whenFetchWorkflowRuns(
          withJobsPage: workflowRunJobsPage,
        ).thenSuccessWith(defaultRunsPage);

        final result = await adapter.fetchBuilds(jobName, fetchLimit);

        expect(result, isEmpty);
      },
    );

    test(
      ".fetchBuilds() fetches builds using pagination for workflow run jobs",
      () {
        whenFetchWorkflowRuns(withJobsPage: emptyWorkflowRunJobsPage)
            .thenSuccessWith(defaultRunsPage);

        when(githubActionsClientMock.fetchRunJobsNext(emptyWorkflowRunJobsPage))
            .thenSuccessWith(defaultJobsPage);

        final result = adapter.fetchBuilds(jobName, fetchLimit);

        expect(result, completion(equals(defaultBuildData)));
      },
    );

    test(
      ".fetchBuilds() throws a StateError if fetching a workflow runs page fails",
      () {
        whenFetchWorkflowRuns(withJobsPage: defaultJobsPage).thenErrorWith();

        final result = adapter.fetchBuilds(jobName, fetchLimit);

        expect(result, throwsStateError);
      },
    );

    test(
      ".fetchBuilds() throws a StateError if fetching the workflow run jobs fails",
      () {
        whenFetchWorkflowRuns(withJobsPage: defaultJobsPage)
            .thenSuccessWith(defaultRunsPage);

        when(githubActionsClientMock.fetchRunJobs(
          any,
          status: anyNamed('status'),
          perPage: anyNamed('perPage'),
          page: anyNamed('page'),
        )).thenErrorWith();

        final result = adapter.fetchBuilds(jobName, fetchLimit);

        expect(result, throwsStateError);
      },
    );

    test(
      ".fetchBuilds() throws a StateError if paginating through run jobs fails",
      () {
        whenFetchWorkflowRuns(withJobsPage: emptyWorkflowRunJobsPage)
            .thenSuccessWith(defaultRunsPage);

        when(githubActionsClientMock.fetchRunJobsNext(emptyWorkflowRunJobsPage))
            .thenErrorWith();

        final result = adapter.fetchBuilds(jobName, fetchLimit);

        expect(result, throwsStateError);
      },
    );

    test(
      ".fetchBuilds() maps fetched builds statuses according to specification",
      () {
        const conclusions = [
          GithubActionConclusion.success,
          GithubActionConclusion.failure,
          GithubActionConclusion.timedOut,
          GithubActionConclusion.cancelled,
          GithubActionConclusion.neutral,
          GithubActionConclusion.actionRequired,
          null,
        ];

        const expectedStatuses = [
          BuildStatus.successful,
          BuildStatus.failed,
          BuildStatus.failed,
          BuildStatus.unknown,
          BuildStatus.unknown,
          BuildStatus.unknown,
          BuildStatus.unknown,
        ];

        final expectedBuilds = testData.generateBuildDataByStatuses(
          statuses: expectedStatuses,
        );

        final workflowRuns = testData.generateWorkflowRunsByNumbers(
          runNumbers: [1, 2, 3, 4, 5, 6, 7],
        );
        final workflowRunsPage = WorkflowRunsPage(values: workflowRuns);

        final workflowRunJobs = testData.generateWorkflowRunJobsByConclusions(
            conclusions: conclusions);

        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);

        for (int i = 0; i < workflowRuns.length; ++i) {
          final run = workflowRuns[i];

          when(githubActionsClientMock.fetchRunJobs(
            run.id,
            status: anyNamed('status'),
            page: anyNamed('page'),
            perPage: anyNamed('perPage'),
          )).thenSuccessWith(
            WorkflowRunJobsPage(values: [workflowRunJobs[i]]),
          );
        }

        final result = adapter.fetchBuilds(jobName, fetchLimit);

        expect(result, completion(equals(expectedBuilds)));
      },
    );

    test(
      ".fetchBuilds() maps fetched in-progress jobs to build data with in-progress build statuses",
      () async {
        final workflowRunJob = testData.generateWorkflowRunJob(
          status: GithubActionStatus.inProgress,
        );

        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(
          withJobsPage: workflowRunJobsPage,
        ).thenSuccessWith(defaultRunsPage);

        final result = await adapter.fetchBuilds(jobName, fetchLimit);
        final buildStatuses = result.map((build) => build.buildStatus);

        expect(buildStatuses, everyElement(equals(BuildStatus.inProgress)));
      },
    );

    test(
      ".fetchBuilds() maps fetched in-progress jobs to build data with null duration",
      () async {
        final workflowRunJob = testData.generateWorkflowRunJob(
          status: GithubActionStatus.inProgress,
        );

        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(
          withJobsPage: workflowRunJobsPage,
        ).thenSuccessWith(defaultRunsPage);

        final result = await adapter.fetchBuilds(jobName, fetchLimit);
        final durations = result.map((build) => build.duration);

        expect(durations, everyElement(isNull));
      },
    );

    test(
      ".fetchBuilds() maps fetched run jobs' startedAt date to the completedAt date if the startedAt date is null",
      () async {
        final completedAt = DateTime.now();
        const workflowRun = WorkflowRun(number: 1);
        const workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = WorkflowRunJob(
          name: jobName,
          startedAt: null,
          completedAt: completedAt,
        );

        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchRunJobs(
          any,
          status: anyNamed('status'),
          page: anyNamed('page'),
          perPage: anyNamed('perPage'),
        )).thenSuccessWith(
          WorkflowRunJobsPage(values: [workflowRunJob]),
        );

        final result = await adapter.fetchBuilds(
          jobName,
          fetchLimit,
        );
        final startedAt = result.first.startedAt;

        expect(startedAt, equals(completedAt));
      },
    );

    test(
      ".fetchBuilds() maps fetched run jobs' startedAt date to the DateTime.now() date if the startedAt and completedAt dates are null",
      () async {
        const workflowRun = WorkflowRun(number: 2);
        const workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        const workflowRunJob = WorkflowRunJob(
          name: jobName,
          startedAt: null,
          completedAt: null,
        );

        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchRunJobs(
          any,
          status: anyNamed('status'),
          page: anyNamed('page'),
          perPage: anyNamed('perPage'),
        )).thenSuccessWith(
          const WorkflowRunJobsPage(values: [workflowRunJob]),
        );

        final result = await adapter.fetchBuilds(
          jobName,
          fetchLimit,
        );
        final startedAt = result.first.startedAt;

        expect(startedAt, isNotNull);
      },
    );

    test(
      ".fetchBuilds() maps fetched run jobs' duration to the Duration.zero if the startedAt date is null",
      () async {
        const workflowRun = WorkflowRun(number: 2);
        const workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = WorkflowRunJob(
          name: jobName,
          startedAt: null,
          completedAt: DateTime.now(),
        );

        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchRunJobs(
          any,
          status: anyNamed('status'),
          page: anyNamed('page'),
          perPage: anyNamed('perPage'),
        )).thenSuccessWith(
          WorkflowRunJobsPage(values: [workflowRunJob]),
        );

        final result = await adapter.fetchBuilds(
          jobName,
          fetchLimit,
        );
        final duration = result.first.duration;

        expect(duration, equals(Duration.zero));
      },
    );

    test(
      ".fetchBuilds() maps fetched run jobs' duration to the Duration.zero if the completedAt date is null",
      () async {
        const workflowRun = WorkflowRun(number: 2);
        const workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = WorkflowRunJob(
          name: jobName,
          startedAt: DateTime.now(),
          completedAt: null,
        );

        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchRunJobs(
          any,
          status: anyNamed('status'),
          page: anyNamed('page'),
          perPage: anyNamed('perPage'),
        )).thenSuccessWith(
          WorkflowRunJobsPage(values: [workflowRunJob]),
        );

        final result = await adapter.fetchBuilds(
          jobName,
          fetchLimit,
        );
        final duration = result.first.duration;

        expect(duration, equals(Duration.zero));
      },
    );

    test(
      ".fetchBuilds() maps fetched run jobs' url to the empty string if the url is null",
      () async {
        const workflowRun = WorkflowRun(number: 2);
        const workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        const workflowRunJob = WorkflowRunJob(
          name: jobName,
          url: null,
        );

        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchRunJobs(
          any,
          status: anyNamed('status'),
          page: anyNamed('page'),
          perPage: anyNamed('perPage'),
        )).thenSuccessWith(
          const WorkflowRunJobsPage(values: [workflowRunJob]),
        );

        final result = await adapter.fetchBuilds(
          jobName,
          fetchLimit,
        );
        final url = result.first.url;

        expect(url, equals(''));
      },
    );

    test(
      ".fetchBuildsAfter() fetches all builds after the given one",
      () {
        final runsPage = WorkflowRunsPage(
          values: testData.generateWorkflowRunsByNumbers(
            runNumbers: [4, 3, 2, 1],
          ),
        );

        final expected = testData.generateBuildDataByNumbers(
          buildNumbers: [4, 3, 2],
        );

        final lastBuild = testData.generateBuildData(buildNumber: 1);

        whenFetchWorkflowRuns(withJobsPage: defaultJobsPage)
            .thenSuccessWith(runsPage);

        final result = adapter.fetchBuildsAfter(jobName, lastBuild);

        expect(result, completion(equals(expected)));
      },
    );

    test(
      ".fetchBuildsAfter() fetches builds with a greater run number than the given if the given number is not found",
      () {
        final runsPage = WorkflowRunsPage(
          values: testData.generateWorkflowRunsByNumbers(
            runNumbers: [7, 6, 5, 3, 2, 1],
          ),
        );

        final expected = testData.generateBuildDataByNumbers(
          buildNumbers: [7, 6, 5],
        );

        final lastBuild = testData.generateBuildData(buildNumber: 4);

        whenFetchWorkflowRuns(
          withJobsPage: defaultJobsPage,
        ).thenSuccessWith(runsPage);

        final result = adapter.fetchBuildsAfter(jobName, lastBuild);

        expect(result, completion(equals(expected)));
      },
    );

    test(
      ".fetchBuildsAfter() returns an empty list if there are no new builds",
      () {
        final runsPage = WorkflowRunsPage(
          values: testData.generateWorkflowRunsByNumbers(
            runNumbers: [4, 3, 2, 1],
          ),
        );

        final lastBuild = testData.generateBuildData(buildNumber: 4);

        whenFetchWorkflowRuns(withJobsPage: defaultJobsPage)
            .thenSuccessWith(runsPage);

        final result = adapter.fetchBuildsAfter(jobName, lastBuild);

        expect(result, completion(isEmpty));
      },
    );

    test(
      ".fetchBuildsAfter() returns an empty list if the client returns workflow runs with the queued status",
      () async {
        final queuedRun = testData.generateWorkflowRun(
          runNumber: 2,
          status: GithubActionStatus.queued,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [queuedRun]);

        final buildData = testData.generateBuildData(buildNumber: 1);

        whenFetchWorkflowRuns(
          withJobsPage: defaultJobsPage,
        ).thenSuccessWith(workflowRunsPage);

        final result = await adapter.fetchBuildsAfter(
          jobName,
          buildData,
        );

        expect(result, isEmpty);
      },
    );

    test(
      ".fetchBuildsAfter() returns an empty list if the client returns workflow runs with the skipped conclusion",
      () async {
        final skippedRun = testData.generateWorkflowRun(
          runNumber: 2,
          conclusion: GithubActionConclusion.skipped,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [skippedRun]);

        final buildData = testData.generateBuildData(buildNumber: 1);

        whenFetchWorkflowRuns(
          withJobsPage: defaultJobsPage,
        ).thenSuccessWith(workflowRunsPage);

        final result = await adapter.fetchBuildsAfter(jobName, buildData);

        expect(result, isEmpty);
      },
    );

    test(
      ".fetchBuildsAfter() returns an empty list if the client returns workflow run jobs with the skipped conclusion",
      () async {
        final skippedJob = testData.generateWorkflowRunJob(
          conclusion: GithubActionConclusion.skipped,
        );
        final workflowRunJobsPage = WorkflowRunJobsPage(values: [skippedJob]);

        final buildData = testData.generateBuildData(buildNumber: 1);

        whenFetchWorkflowRuns(
          withJobsPage: workflowRunJobsPage,
        ).thenSuccessWith(defaultRunsPage);

        final result = await adapter.fetchBuildsAfter(jobName, buildData);

        expect(result, isEmpty);
      },
    );

    test(
      ".fetchBuildsAfter() returns an empty list if the client returns workflow run jobs with the queued status",
      () async {
        final queuedJob = testData.generateWorkflowRunJob(
          status: GithubActionStatus.queued,
        );
        final workflowRunJobsPage = WorkflowRunJobsPage(values: [queuedJob]);

        final buildData = testData.generateBuildData(buildNumber: 1);

        whenFetchWorkflowRuns(
          withJobsPage: workflowRunJobsPage,
        ).thenSuccessWith(defaultRunsPage);

        final result = await adapter.fetchBuildsAfter(jobName, buildData);

        expect(result, isEmpty);
      },
    );

    test(
      ".fetchBuildsAfter() fetches builds using pagination for workflow runs",
      () {
        final firstPage = WorkflowRunsPage(
          page: 1,
          nextPageUrl: testData.url,
          values: testData.generateWorkflowRunsByNumbers(
            runNumbers: [4, 3],
          ),
        );
        final secondPage = WorkflowRunsPage(
          page: 2,
          values: testData.generateWorkflowRunsByNumbers(
            runNumbers: [2, 1],
          ),
        );

        final firstBuild = testData.generateBuildData(buildNumber: 1);
        final expected = testData.generateBuildDataByNumbers(
          buildNumbers: [4, 3, 2],
        );

        whenFetchWorkflowRuns(withJobsPage: defaultJobsPage)
            .thenSuccessWith(firstPage);

        when(githubActionsClientMock.fetchWorkflowRunsNext(firstPage))
            .thenSuccessWith(secondPage);

        final result = adapter.fetchBuildsAfter(jobName, firstBuild);

        expect(result, completion(equals(expected)));
      },
    );

    test(
      ".fetchBuildsAfter() fetches builds using pagination for run jobs",
      () {
        final runsPage = WorkflowRunsPage(
          values: testData.generateWorkflowRunsByNumbers(
            runNumbers: [4, 3, 2, 1],
          ),
        );

        final expected = testData.generateBuildDataByNumbers(
          buildNumbers: [4, 3, 2],
        );

        final lastBuild = testData.generateBuildData(buildNumber: 1);

        whenFetchWorkflowRuns(withJobsPage: emptyWorkflowRunJobsPage)
            .thenSuccessWith(runsPage);

        when(githubActionsClientMock.fetchRunJobsNext(emptyWorkflowRunJobsPage))
            .thenSuccessWith(defaultJobsPage);

        final result = adapter.fetchBuildsAfter(jobName, lastBuild);

        expect(result, completion(equals(expected)));
      },
    );

    test(
      ".fetchBuildsAfter() throws a StateError if fetching a workflow runs page fails",
      () {
        whenFetchWorkflowRuns(withJobsPage: defaultJobsPage)
            .thenSuccessWith(defaultRunsPage);

        when(githubActionsClientMock.fetchWorkflowRuns(
          any,
          status: anyNamed('status'),
          perPage: anyNamed('perPage'),
          page: anyNamed('page'),
        )).thenErrorWith();

        final firstBuild = testData.generateBuildData(buildNumber: 1);

        final result = adapter.fetchBuildsAfter(jobName, firstBuild);

        expect(result, throwsStateError);
      },
    );

    test(
      ".fetchBuildsAfter() throws a StateError if paginating through workflow runs fails",
      () {
        final firstPage = WorkflowRunsPage(
          nextPageUrl: testData.url,
          values: testData.generateWorkflowRunsByNumbers(
            runNumbers: [4, 3],
          ),
        );

        whenFetchWorkflowRuns(withJobsPage: defaultJobsPage)
            .thenSuccessWith(firstPage);

        when(githubActionsClientMock.fetchWorkflowRunsNext(firstPage))
            .thenErrorWith();

        final firstBuild = testData.generateBuildData(buildNumber: 1);

        final result = adapter.fetchBuildsAfter(jobName, firstBuild);

        expect(result, throwsStateError);
      },
    );

    test(
      ".fetchBuildsAfter() throws a StateError if fetching the run job fails",
      () {
        whenFetchWorkflowRuns().thenSuccessWith(defaultRunsPage);

        when(githubActionsClientMock.fetchRunJobs(
          any,
          perPage: anyNamed('perPage'),
          page: anyNamed('page'),
        )).thenErrorWith();

        final firstBuild = testData.generateBuildData(buildNumber: 1);

        final result = adapter.fetchBuildsAfter(jobName, firstBuild);

        expect(result, throwsStateError);
      },
    );

    test(
      ".fetchBuildsAfter() throws a StateError if paginating through run jobs fails",
      () {
        whenFetchWorkflowRuns(withJobsPage: emptyWorkflowRunJobsPage)
            .thenSuccessWith(defaultRunsPage);

        when(githubActionsClientMock.fetchRunJobsNext(emptyWorkflowRunJobsPage))
            .thenErrorWith();

        final firstBuild = testData.generateBuildData(buildNumber: 1);

        final result = adapter.fetchBuildsAfter(jobName, firstBuild);

        expect(result, throwsStateError);
      },
    );

    test(
      ".fetchBuildsAfter() maps fetched builds statuses according to specification",
      () {
        const conclusions = [
          GithubActionConclusion.success,
          GithubActionConclusion.failure,
          GithubActionConclusion.timedOut,
          GithubActionConclusion.cancelled,
          GithubActionConclusion.neutral,
          GithubActionConclusion.actionRequired,
          null,
        ];

        const expectedStatuses = [
          BuildStatus.successful,
          BuildStatus.failed,
          BuildStatus.failed,
          BuildStatus.unknown,
          BuildStatus.unknown,
          BuildStatus.unknown,
          BuildStatus.unknown,
        ];

        final expectedBuilds = testData.generateBuildDataByStatuses(
          statuses: expectedStatuses,
        );

        final workflowRuns = testData.generateWorkflowRunsByNumbers(
          runNumbers: [1, 2, 3, 4, 5, 6, 7],
        );
        final workflowRunsPage = WorkflowRunsPage(values: workflowRuns);

        final workflowRunJobs = testData.generateWorkflowRunJobsByConclusions(
            conclusions: conclusions);

        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);

        for (int i = 0; i < workflowRuns.length; ++i) {
          final run = workflowRuns[i];

          when(githubActionsClientMock.fetchRunJobs(
            run.id,
            status: anyNamed('status'),
            page: anyNamed('page'),
            perPage: anyNamed('perPage'),
          )).thenSuccessWith(
            WorkflowRunJobsPage(values: [workflowRunJobs[i]]),
          );
        }

        final firstBuild = testData.generateBuildData(buildNumber: 0);

        final result = adapter.fetchBuildsAfter(jobName, firstBuild);

        expect(result, completion(equals(expectedBuilds)));
      },
    );

    test(
      ".fetchBuildsAfter() maps fetched in-progress jobs to build data with in-progress build statuses",
      () async {
        final workflowRun = testData.generateWorkflowRun(runNumber: 2);
        final workflowRunsPage = WorkflowRunsPage(
          values: [workflowRun],
        );

        final inProgressBuild = testData.generateWorkflowRunJob(
          status: GithubActionStatus.inProgress,
        );
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [inProgressBuild],
        );

        whenFetchWorkflowRuns(
          withJobsPage: workflowRunJobsPage,
        ).thenSuccessWith(workflowRunsPage);

        final firstBuild = testData.generateBuildData(buildNumber: 1);

        final result = await adapter.fetchBuildsAfter(
          jobName,
          firstBuild,
        );
        final buildStatuses = result.map((build) => build.buildStatus);

        expect(buildStatuses, everyElement(equals(BuildStatus.inProgress)));
      },
    );

    test(
      ".fetchBuildsAfter() maps fetched run in-progress jobs to build data with null duration",
      () async {
        final workflowRun = testData.generateWorkflowRun(runNumber: 2);
        final workflowRunsPage = WorkflowRunsPage(
          values: [workflowRun],
        );

        final inProgressBuild = testData.generateWorkflowRunJob(
          status: GithubActionStatus.inProgress,
        );
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [inProgressBuild],
        );

        whenFetchWorkflowRuns(
          withJobsPage: workflowRunJobsPage,
        ).thenSuccessWith(workflowRunsPage);

        final firstBuild = testData.generateBuildData(buildNumber: 1);

        final result = await adapter.fetchBuildsAfter(
          jobName,
          firstBuild,
        );
        final durations = result.map((build) => build.duration);

        expect(durations, everyElement(isNull));
      },
    );

    test(
      ".fetchBuildsAfter() maps fetched run jobs' startedAt date to the completedAt date if the startedAt date is null",
      () async {
        final completedAt = DateTime.now();
        const workflowRun = WorkflowRun(number: 2);
        const workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = WorkflowRunJob(
          name: jobName,
          startedAt: null,
          completedAt: completedAt,
        );

        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchRunJobs(
          any,
          status: anyNamed('status'),
          page: anyNamed('page'),
          perPage: anyNamed('perPage'),
        )).thenSuccessWith(
          WorkflowRunJobsPage(values: [workflowRunJob]),
        );

        final firstBuild = testData.generateBuildData(buildNumber: 1);

        final result = await adapter.fetchBuildsAfter(
          jobName,
          firstBuild,
        );
        final startedAt = result.first.startedAt;

        expect(startedAt, equals(completedAt));
      },
    );

    test(
      ".fetchBuildsAfter() maps fetched run jobs' startedAt date to the DateTime.now() date if the startedAt and completedAt dates are null",
      () async {
        const workflowRun = WorkflowRun(number: 2);
        const workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        const workflowRunJob = WorkflowRunJob(
          name: jobName,
          startedAt: null,
          completedAt: null,
        );

        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchRunJobs(
          any,
          status: anyNamed('status'),
          page: anyNamed('page'),
          perPage: anyNamed('perPage'),
        )).thenSuccessWith(
          const WorkflowRunJobsPage(values: [workflowRunJob]),
        );

        final firstBuild = testData.generateBuildData(buildNumber: 1);

        final result = await adapter.fetchBuildsAfter(
          jobName,
          firstBuild,
        );
        final startedAt = result.first.startedAt;

        expect(startedAt, isNotNull);
      },
    );

    test(
      ".fetchBuildsAfter() maps fetched run jobs' duration to the Duration.zero if the startedAt date is null",
      () async {
        const workflowRun = WorkflowRun(number: 2);
        const workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = WorkflowRunJob(
          name: jobName,
          startedAt: null,
          completedAt: DateTime.now(),
        );

        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchRunJobs(
          any,
          status: anyNamed('status'),
          page: anyNamed('page'),
          perPage: anyNamed('perPage'),
        )).thenSuccessWith(
          WorkflowRunJobsPage(values: [workflowRunJob]),
        );

        final firstBuild = testData.generateBuildData(buildNumber: 1);

        final result = await adapter.fetchBuildsAfter(
          jobName,
          firstBuild,
        );
        final duration = result.first.duration;

        expect(duration, equals(Duration.zero));
      },
    );

    test(
      ".fetchBuildsAfter() maps fetched run jobs' duration to the Duration.zero if the completedAt date is null",
      () async {
        const workflowRun = WorkflowRun(number: 2);
        const workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = WorkflowRunJob(
          name: jobName,
          startedAt: DateTime.now(),
          completedAt: null,
        );

        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchRunJobs(
          any,
          status: anyNamed('status'),
          page: anyNamed('page'),
          perPage: anyNamed('perPage'),
        )).thenSuccessWith(
          WorkflowRunJobsPage(values: [workflowRunJob]),
        );

        final firstBuild = testData.generateBuildData(buildNumber: 1);

        final result = await adapter.fetchBuildsAfter(
          jobName,
          firstBuild,
        );
        final duration = result.first.duration;

        expect(duration, equals(Duration.zero));
      },
    );

    test(
      ".fetchBuildsAfter() maps fetched run jobs' url to the empty string if the url is null",
      () async {
        const workflowRun = WorkflowRun(number: 2);
        const workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        const workflowRunJob = WorkflowRunJob(
          name: jobName,
          url: null,
        );

        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchRunJobs(
          any,
          status: anyNamed('status'),
          page: anyNamed('page'),
          perPage: anyNamed('perPage'),
        )).thenSuccessWith(
          const WorkflowRunJobsPage(values: [workflowRunJob]),
        );

        final firstBuild = testData.generateBuildData(buildNumber: 1);

        final result = await adapter.fetchBuildsAfter(
          jobName,
          firstBuild,
        );
        final url = result.first.url;

        expect(url, equals(''));
      },
    );

    test(
      ".fetchCoverage() throws an ArgumentError if the given build is null",
      () {
        final result = adapter.fetchCoverage(null);

        expect(result, throwsArgumentError);
      },
    );

    test(
      ".fetchCoverage() fetches coverage for the given build",
      () async {
        final expectedCoverage = defaultBuild.coverage;

        whenFetchCoverage(withWorkflowRun: defaultWorkflowRun)
            .thenSuccessWith(defaultArtifactsPage);
        whenDecodeCoverage(withArtifactBytes: coverageBytes)
            .thenReturn(coverageBytes);

        final actualCoverage = await adapter.fetchCoverage(defaultBuild);

        expect(actualCoverage, equals(expectedCoverage));
      },
    );

    test(
      ".fetchCoverage() returns null if fetching a workflow run for the given build returns null",
      () async {
        whenFetchCoverage(withWorkflowRun: null)
            .thenSuccessWith(defaultArtifactsPage);

        final result = await adapter.fetchCoverage(defaultBuild);

        expect(result, isNull);
      },
    );

    test(
      ".fetchCoverage() returns null if the coverage summary artifact is not found",
      () async {
        const artifactsPage = WorkflowRunArtifactsPage(
          values: [WorkflowRunArtifact(name: 'test.json')],
        );
        whenFetchCoverage(withWorkflowRun: defaultWorkflowRun)
            .thenSuccessWith(artifactsPage);

        final result = await adapter.fetchCoverage(defaultBuild);

        expect(result, isNull);
      },
    );

    test(
      ".fetchCoverage() does not download any artifacts if the coverage summary artifact is not found",
      () async {
        const artifactsPage = WorkflowRunArtifactsPage(
          values: [WorkflowRunArtifact(name: 'test.json')],
        );

        whenFetchCoverage(withWorkflowRun: defaultWorkflowRun)
            .thenSuccessWith(artifactsPage);

        final result = await adapter.fetchCoverage(defaultBuild);

        expect(result, isNull);
        verifyNever(githubActionsClientMock.downloadRunArtifactZip(any));
      },
    );

    test(
      ".fetchCoverage() returns null if an artifact archive does not contain the coverage summary json",
      () async {
        whenFetchCoverage(withWorkflowRun: defaultWorkflowRun)
            .thenSuccessWith(defaultArtifactsPage);
        whenDecodeCoverage(withArtifactBytes: coverageBytes).thenReturn(null);

        final result = await adapter.fetchCoverage(defaultBuild);

        expect(result, isNull);
      },
    );

    test(
      ".fetchCoverage() fetches coverage using pagination for run artifacts",
      () async {
        final expectedCoverage = defaultBuild.coverage;

        whenFetchCoverage(withWorkflowRun: defaultWorkflowRun)
            .thenSuccessWith(artifactsPage);
        whenDecodeCoverage(withArtifactBytes: coverageBytes)
            .thenReturn(coverageBytes);
        when(githubActionsClientMock.fetchRunArtifactsNext(artifactsPage))
            .thenSuccessWith(defaultArtifactsPage);

        final actualCoverage = await adapter.fetchCoverage(defaultBuild);

        expect(actualCoverage, equals(expectedCoverage));
        verify(
          githubActionsClientMock.fetchRunArtifactsNext(artifactsPage),
        ).called(once);
      },
    );

    test(
      ".fetchCoverage() throws a StateError if fetching a workflow run fails for the given build",
      () {
        whenFetchCoverage(withWorkflowRun: defaultWorkflowRun)
            .thenSuccessWith(artifactsPage);
        when(githubActionsClientMock.fetchWorkflowRunByUrl(any))
            .thenErrorWith();

        final result = adapter.fetchCoverage(defaultBuild);

        expect(result, throwsStateError);
      },
    );

    test(
      ".fetchCoverage() throws a StateError if fetching the coverage artifact fails",
      () {
        whenFetchCoverage(withWorkflowRun: defaultWorkflowRun).thenErrorWith();

        final result = adapter.fetchCoverage(defaultBuild);

        expect(result, throwsStateError);
      },
    );

    test(
      ".fetchCoverage() throws a StateError if paginating through coverage artifacts fails",
      () {
        whenFetchCoverage(withWorkflowRun: defaultWorkflowRun)
            .thenSuccessWith(artifactsPage);
        when(githubActionsClientMock.fetchRunArtifactsNext(artifactsPage))
            .thenErrorWith();

        final result = adapter.fetchCoverage(defaultBuild);

        expect(result, throwsStateError);
      },
    );

    test(
      ".fetchCoverage() throws a StateError if downloading an artifact archive fails",
      () {
        whenFetchCoverage(withWorkflowRun: defaultWorkflowRun)
            .thenSuccessWith(defaultArtifactsPage);
        when(githubActionsClientMock.downloadRunArtifactZip(any))
            .thenErrorWith();

        final result = adapter.fetchCoverage(defaultBuild);

        expect(result, throwsStateError);
      },
    );

    test(
      ".fetchOneBuild() throws an ArgumentError if the given job name is null",
      () {
        final buildFuture = adapter.fetchOneBuild(null, buildNumber);

        expect(buildFuture, throwsArgumentError);
      },
    );

    test(
      ".fetchOneBuild() throws an ArgumentError if the given build number is null",
      () {
        final buildFuture = adapter.fetchOneBuild(jobName, null);

        expect(buildFuture, throwsArgumentError);
      },
    );

    test(
      ".fetchOneBuild() fetches the first workflow runs page with the default number of builds per page",
      () async {
        const workflowRunsPage = WorkflowRunsPage(values: []);
        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);

        await adapter.fetchOneBuild(jobName, buildNumber);

        verify(githubActionsClientMock.fetchWorkflowRuns(
          any,
          status: anyNamed('status'),
          page: 1,
          perPage: GithubActionsSourceClientAdapter.defaultPerPage,
        )).called(once);
      },
    );

    test(
      ".fetchOneBuild() returns null if there are no workflow runs",
      () {
        const emptyRunsPage = WorkflowRunsPage(values: []);
        whenFetchWorkflowRuns().thenSuccessWith(emptyRunsPage);

        final buildFuture = adapter.fetchOneBuild(jobName, buildNumber);

        expect(buildFuture, completion(isNull));
      },
    );

    test(
      ".fetchOneBuild() returns null if the GitHub Actions client returns a first workflow runs page with values equal to null",
      () {
        const workflowRunsPage = WorkflowRunsPage();
        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);

        final buildFuture = adapter.fetchOneBuild(jobName, buildNumber);

        expect(buildFuture, completion(isNull));
      },
    );

    test(
      ".fetchOneBuild() returns null if the workflow run with the given build number has the skipped conclusion",
      () {
        const workflowRun = WorkflowRun(
          number: buildNumber,
          conclusion: GithubActionConclusion.skipped,
        );
        const workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);

        final buildFuture = adapter.fetchOneBuild(jobName, buildNumber);

        expect(buildFuture, completion(isNull));
      },
    );

    test(
      ".fetchOneBuild() returns null if the workflow run with the given build number has the queued status",
      () async {
        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
          status: GithubActionStatus.queued,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);

        final buildFuture = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(buildFuture, isNull);
      },
    );

    test(
      ".fetchOneBuild() returns null if there is no workflow run with the given number",
      () {
        final workflowRuns = testData.generateWorkflowRunsByNumbers(
          runNumbers: [4, 3, 1],
        );
        final workflowRunsPage = WorkflowRunsPage(values: workflowRuns);
        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);

        final buildFuture = adapter.fetchOneBuild(jobName, 2);

        expect(buildFuture, completion(isNull));
      },
    );

    test(
      ".fetchOneBuild() throws a StateError if the fetching of the workflow runs fails",
      () {
        whenFetchWorkflowRuns().thenErrorWith();

        final buildFuture = adapter.fetchOneBuild(jobName, buildNumber);

        expect(buildFuture, throwsStateError);
      },
    );

    test(
      ".fetchOneBuild() fetches the workflow run with the given number using the pagination if the first page does not contain the run with the given build number",
      () async {
        final workflowRuns = testData.generateWorkflowRunsByNumbers(
          runNumbers: [2],
        );
        final workflowRunsPage = WorkflowRunsPage(
          values: workflowRuns,
          nextPageUrl: testData.url,
        );
        const nextWorkflowRunsPage = WorkflowRunsPage();
        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchWorkflowRunsNext(any))
            .thenSuccessWith(nextWorkflowRunsPage);

        await adapter.fetchOneBuild(jobName, buildNumber);

        verify(githubActionsClientMock.fetchWorkflowRunsNext(workflowRunsPage))
            .called(once);
      },
    );

    test(
      ".fetchOneBuild() does not fetch the next workflow runs page if the current page contains the workflow run with a number equal to the given build number",
      () async {
        const workflowRunJobsPage = WorkflowRunJobsPage(values: []);
        final workflowRunsPage = WorkflowRunsPage(
          values: const [],
          nextPageUrl: testData.url,
        );
        final nextWorkflowRuns = testData.generateWorkflowRunsByNumbers(
          runNumbers: [buildNumber],
        );
        final nextWorkflowRunsPage = WorkflowRunsPage(values: nextWorkflowRuns);

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchWorkflowRunsNext(workflowRunsPage))
            .thenSuccessWith(nextWorkflowRunsPage);

        await adapter.fetchOneBuild(jobName, buildNumber);

        verifyNever(githubActionsClientMock
            .fetchWorkflowRunsNext(nextWorkflowRunsPage));
      },
    );

    test(
      ".fetchOneBuild() throws a StateError if paginating workflow runs fails",
      () {
        final workflowRuns = testData.generateWorkflowRunsByNumbers(
          runNumbers: [4, 3, 2],
        );
        final workflowRunsPage = WorkflowRunsPage(
          values: workflowRuns,
          nextPageUrl: testData.url,
        );
        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchWorkflowRunsNext(any))
            .thenErrorWith();

        final buildFuture = adapter.fetchOneBuild(jobName, buildNumber);

        expect(buildFuture, throwsStateError);
      },
    );

    test(
      ".fetchOneBuild() fetches the first workflow run jobs page for the workflow run with the given build number",
      () async {
        const runId = 1;
        final workflowRun = testData.generateWorkflowRun(
          id: runId,
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = testData.generateWorkflowRunJob();
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        await adapter.fetchOneBuild(jobName, buildNumber);

        verify(githubActionsClientMock.fetchRunJobs(
          runId,
          status: anyNamed('status'),
          page: 1,
          perPage: anyNamed('perPage'),
        )).called(once);
      },
    );

    test(
      ".fetchOneBuild() returns null if the first workflow run jobs page does not contain the job with the given name and does not have the next page",
      () {
        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        const workflowRunJobsPage = WorkflowRunJobsPage(values: []);

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final buildFuture = adapter.fetchOneBuild(jobName, buildNumber);

        expect(buildFuture, completion(isNull));
      },
    );

    test(
      ".fetchOneBuild() returns null if a job with the given name has the skipped conclusion",
      () {
        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        const skippedRunJob = WorkflowRunJob(
          name: jobName,
          conclusion: GithubActionConclusion.skipped,
        );
        const workflowRunJobsPage = WorkflowRunJobsPage(
          values: [skippedRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final buildFuture = adapter.fetchOneBuild(jobName, buildNumber);

        expect(buildFuture, completion(isNull));
      },
    );

    test(
      ".fetchOneBuild() returns null if a job with the given name has the queued status",
      () async {
        final workflowRunsPage = WorkflowRunsPage(values: [
          testData.generateWorkflowRun(runNumber: buildNumber),
        ]);
        const queuedJob = WorkflowRunJob(
          name: jobName,
          status: GithubActionStatus.queued,
        );
        const workflowRunJobsPage = WorkflowRunJobsPage(
          values: [queuedJob],
        );

        whenFetchWorkflowRuns(
          withJobsPage: workflowRunJobsPage,
        ).thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build, isNull);
      },
    );

    test(
      ".fetchOneBuild() throws a StateError if the fetching of the workflow run jobs fails",
      () {
        const runId = 1;
        final workflowRun = testData.generateWorkflowRun(
          id: runId,
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);

        whenFetchWorkflowRuns().thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchRunJobs(
          runId,
          status: anyNamed('status'),
          page: anyNamed('page'),
          perPage: anyNamed('perPage'),
        )).thenErrorWith();

        final buildFuture = adapter.fetchOneBuild(jobName, buildNumber);

        expect(buildFuture, throwsStateError);
      },
    );

    test(
      ".fetchOneBuild() fetches the workflow run job with the given name using the pagination if the first page does not contain the job with the given name",
      () async {
        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = testData.generateWorkflowRunJob();
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: const [],
          nextPageUrl: testData.url,
        );
        final nextWorkflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchRunJobsNext(workflowRunJobsPage))
            .thenSuccessWith(nextWorkflowRunJobsPage);

        await adapter.fetchOneBuild(jobName, buildNumber);

        verify(githubActionsClientMock.fetchRunJobsNext(
          workflowRunJobsPage,
        )).called(once);
      },
    );

    test(
      ".fetchOneBuild() does not fetch the next workflow run jobs page if the current one contains the job with the given name",
      () async {
        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        const workflowRunJob = WorkflowRunJob(name: 'name');
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: const [workflowRunJob],
          nextPageUrl: testData.url,
        );
        final nextWorkflowRunJob = testData.generateWorkflowRunJob();
        final nextWorkflowRunJobsPage = WorkflowRunJobsPage(
          values: [nextWorkflowRunJob],
          nextPageUrl: testData.url,
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchRunJobsNext(workflowRunJobsPage))
            .thenSuccessWith(nextWorkflowRunJobsPage);

        await adapter.fetchOneBuild(jobName, buildNumber);

        verifyNever(
          githubActionsClientMock.fetchRunJobsNext(nextWorkflowRunJobsPage),
        );
      },
    );

    test(
      ".fetchOneBuild() returns null if the next workflow run jobs page does not have the job with the given name",
      () {
        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: const [],
          nextPageUrl: testData.url,
        );
        const nextWorkflowRunJobsPage = WorkflowRunJobsPage(
          values: [],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchRunJobsNext(workflowRunJobsPage))
            .thenSuccessWith(nextWorkflowRunJobsPage);

        final buildFuture = adapter.fetchOneBuild(jobName, buildNumber);

        expect(buildFuture, completion(isNull));
      },
    );

    test(
      ".fetchOneBuild() throws a StateError if paginating workflow run jobs fails",
      () {
        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: const [],
          nextPageUrl: testData.url,
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);
        when(githubActionsClientMock.fetchRunJobsNext(any)).thenErrorWith();

        final buildFuture = adapter.fetchOneBuild(jobName, buildNumber);

        expect(buildFuture, throwsStateError);
      },
    );

    test(
      ".fetchOneBuild() maps the workflow run's number to the build number",
      () async {
        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = testData.generateWorkflowRunJob();
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build.buildNumber, equals(buildNumber));
      },
    );

    test(
      ".fetchOneBuild() maps the workflow run job's startedAt to the build startedAt",
      () async {
        final expectedStartedAt = DateTime(2007);

        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = WorkflowRunJob(
          name: jobName,
          startedAt: expectedStartedAt,
        );
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build.startedAt, equals(expectedStartedAt));
      },
    );

    test(
      ".fetchOneBuild() maps the workflow run job's completedAt to the build's startedAt if the job's startedAt is null",
      () async {
        final expectedStartedAt = DateTime(2007);

        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = WorkflowRunJob(
          name: jobName,
          completedAt: expectedStartedAt,
        );
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build.startedAt, equals(expectedStartedAt));
      },
    );

    test(
      ".fetchOneBuild() applies the current date to the build's startedAt if the fetched job's startedAt and completedAt are null",
      () async {
        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        const workflowRunJob = WorkflowRunJob(
          name: jobName,
        );
        const workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build.startedAt, isNotNull);
      },
    );

    test(
      ".fetchOneBuild() maps fetched workflow run job's success conclusion to successful build status",
      () async {
        const conclusion = GithubActionConclusion.success;
        const expectedConclusion = BuildStatus.successful;

        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = testData.generateWorkflowRunJob(
          conclusion: conclusion,
        );
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build.buildStatus, equals(expectedConclusion));
      },
    );

    test(
      ".fetchOneBuild() maps fetched workflow run job's failure conclusion to failed build status",
      () async {
        const conclusion = GithubActionConclusion.failure;
        const expectedConclusion = BuildStatus.failed;

        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = testData.generateWorkflowRunJob(
          conclusion: conclusion,
        );
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build.buildStatus, equals(expectedConclusion));
      },
    );

    test(
      ".fetchOneBuild() maps fetched workflow run job's timed out conclusion to failed build status",
      () async {
        const conclusion = GithubActionConclusion.timedOut;
        const expectedConclusion = BuildStatus.failed;

        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = testData.generateWorkflowRunJob(
          conclusion: conclusion,
        );
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build.buildStatus, equals(expectedConclusion));
      },
    );

    test(
      ".fetchOneBuild() maps fetched workflow run job's conclusion different from success, failure or timed out to unknown build status",
      () async {
        const conclusion = GithubActionConclusion.actionRequired;
        const expectedConclusion = BuildStatus.unknown;

        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = testData.generateWorkflowRunJob(
          conclusion: conclusion,
        );
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build.buildStatus, equals(expectedConclusion));
      },
    );

    test(
      ".fetchOneBuild() maps fetched in-progress workflow run job to in-progress build data",
      () async {
        final workflowRunsPage = WorkflowRunsPage(values: [
          testData.generateWorkflowRun(
            runNumber: buildNumber,
          ),
        ]);
        final workflowRunJob = testData.generateWorkflowRunJob(
          status: GithubActionStatus.inProgress,
        );
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build.buildStatus, equals(BuildStatus.inProgress));
      },
    );

    test(
      ".fetchOneBuild() maps fetched in-progress workflow run job to build data with null duration",
      () async {
        final workflowRunsPage = WorkflowRunsPage(values: [
          testData.generateWorkflowRun(
            runNumber: buildNumber,
          ),
        ]);
        final workflowRunJob = testData.generateWorkflowRunJob(
          status: GithubActionStatus.inProgress,
        );
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build.duration, isNull);
      },
    );

    test(
      ".fetchOneBuild() calculates duration based on the job's startedAt and completedAt timestamps",
      () async {
        final startedAt = DateTime(2020);
        final completedAt = DateTime(2021);
        final expectedDuration = completedAt.difference(startedAt);

        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = WorkflowRunJob(
          name: jobName,
          startedAt: startedAt,
          completedAt: completedAt,
        );
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build.duration, equals(expectedDuration));
      },
    );

    test(
      ".fetchOneBuild() sets the zero duration if the fetched workflow run job's startedAt is null",
      () async {
        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = WorkflowRunJob(
          name: jobName,
          completedAt: DateTime(2021),
        );
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build.duration, equals(Duration.zero));
      },
    );

    test(
      ".fetchOneBuild() sets the zero duration if the fetched workflow run job's completedAt is null",
      () async {
        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = WorkflowRunJob(
          name: jobName,
          startedAt: DateTime(2021),
        );
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build.duration, equals(Duration.zero));
      },
    );

    test(
      ".fetchOneBuild() maps the workflow run job's name to the build's workflow name",
      () async {
        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        const workflowRunJob = WorkflowRunJob(name: jobName);
        const workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build.workflowName, equals(jobName));
      },
    );

    test(
      ".fetchOneBuild() maps the workflow run job's url to the build's url",
      () async {
        const url = 'url';
        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        const workflowRunJob = WorkflowRunJob(
          name: jobName,
          url: url,
        );
        const workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build.url, equals(url));
      },
    );

    test(
      ".fetchOneBuild() sets the empty build url if the fetched job's url is null",
      () async {
        final workflowRun = testData.generateWorkflowRun(
          runNumber: buildNumber,
        );
        final workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        const workflowRunJob = WorkflowRunJob(name: jobName);
        const workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build.url, isEmpty);
      },
    );

    test(
      ".fetchOneBuild() maps the workflow run's api url to the build's api url",
      () async {
        const expectedApiUrl = 'apiUrl';

        const workflowRun = WorkflowRun(
          number: buildNumber,
          apiUrl: expectedApiUrl,
        );
        const workflowRunsPage = WorkflowRunsPage(values: [workflowRun]);
        final workflowRunJob = testData.generateWorkflowRunJob();
        final workflowRunJobsPage = WorkflowRunJobsPage(
          values: [workflowRunJob],
        );

        whenFetchWorkflowRuns(withJobsPage: workflowRunJobsPage)
            .thenSuccessWith(workflowRunsPage);

        final build = await adapter.fetchOneBuild(jobName, buildNumber);

        expect(build.apiUrl, equals(expectedApiUrl));
      },
    );

    test(
      ".dispose() closes the Github Actions client",
      () {
        adapter.dispose();

        verify(githubActionsClientMock.close()).called(once);
      },
    );
  });
}

class _ArchiveHelperMock extends Mock implements ArchiveHelper {}

class _ArchiveMock extends Mock implements Archive {}
