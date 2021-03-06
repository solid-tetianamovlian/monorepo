// Use of this source code is governed by the Apache License, Version 2.0
// that can be found in the LICENSE file.

import 'package:ci_integration/client/buildkite/models/buildkite_organization.dart';
import 'package:ci_integration/client/buildkite/models/buildkite_pipeline.dart';
import 'package:ci_integration/client/buildkite/models/buildkite_token.dart';
import 'package:ci_integration/client/buildkite/models/buildkite_token_scope.dart';
import 'package:ci_integration/source/buildkite/config/validation_delegate/buildkite_source_validation_delegate.dart';
import 'package:ci_integration/source/buildkite/strings/buildkite_strings.dart';
import 'package:ci_integration/util/authorization/authorization.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../../../test_utils/extensions/interaction_result_answer.dart';
import '../../test_utils/buildkite_client_mock.dart';

// ignore_for_file: avoid_redundant_argument_values

void main() {
  group("BuildkiteSourceValidationDelegate", () {
    const organizationSlug = 'organization_slug';
    const pipelineSlug = 'pipeline_slug';

    const buildkiteToken = BuildkiteToken(
      scopes: [
        BuildkiteTokenScope.readBuilds,
      ],
    );
    const readBuildsAndArtifactsScopes = [
      BuildkiteTokenScope.readBuilds,
      BuildkiteTokenScope.readArtifacts
    ];

    const buildkiteOrganization = BuildkiteOrganization(
      id: 'id',
      name: 'name',
      slug: organizationSlug,
    );

    const buildkitePipeline = BuildkitePipeline(
      id: 'id',
      name: 'name',
      slug: pipelineSlug,
    );

    final auth = BearerAuthorization('token');

    final client = BuildkiteClientMock();
    final delegate = BuildkiteSourceValidationDelegate(client);

    tearDown(() {
      reset(client);
    });

    test(
      "throws an ArgumentError if the given client is null",
      () {
        expect(
          () => BuildkiteSourceValidationDelegate(null),
          throwsArgumentError,
        );
      },
    );

    test(
      "creates an instance with the given client",
      () {
        expect(
          () => BuildkiteSourceValidationDelegate(client),
          returnsNormally,
        );
      },
    );

    test(
      ".validateAuth() returns a failure field validation result, if the interaction with the client is not successful",
      () async {
        when(client.fetchToken(auth)).thenErrorWith();

        final result = await delegate.validateAuth(auth);

        expect(result.isFailure, isTrue);
      },
    );

    test(
      ".validateAuth() returns a field validation result with the 'token invalid' additional context, if the interaction with the client is not successful",
      () async {
        when(client.fetchToken(auth)).thenErrorWith();

        final result = await delegate.validateAuth(auth);
        final additionalContext = result.additionalContext;

        expect(additionalContext, equals(BuildkiteStrings.tokenInvalid));
      },
    );

    test(
      ".validateAuth() returns a failure field validation result, if the result of an interaction with the client is null",
      () async {
        when(client.fetchToken(auth)).thenSuccessWith(null);

        final result = await delegate.validateAuth(auth);

        expect(result.isFailure, isTrue);
      },
    );

    test(
      ".validateAuth() returns a field validation result with the 'token invalid' additional context, if the result of an interaction with the client is null",
      () async {
        when(client.fetchToken(auth)).thenSuccessWith(null);

        final result = await delegate.validateAuth(auth);
        final additionalContext = result.additionalContext;

        expect(additionalContext, equals(BuildkiteStrings.tokenInvalid));
      },
    );

    test(
      ".validateAuth() returns a failure field validation result, if the fetched token does not have the read builds token scope",
      () async {
        when(client.fetchToken(auth)).thenSuccessWith(
          const BuildkiteToken(scopes: []),
        );

        final result = await delegate.validateAuth(auth);

        expect(result.isFailure, isTrue);
      },
    );

    test(
      ".validateAuth() returns a field validation result with the 'token does not have read builds scope' additional context, if the fetched token does not have the read builds token scope",
      () async {
        when(client.fetchToken(auth)).thenSuccessWith(
          const BuildkiteToken(scopes: []),
        );

        final result = await delegate.validateAuth(auth);
        final additionalContext = result.additionalContext;

        expect(
          additionalContext,
          equals(BuildkiteStrings.tokenDoesNotHaveReadBuildsScope),
        );
      },
    );

    test(
      ".validateAuth() returns a successful field validation result, if the fetched token is valid, but does not have the read artifacts scope",
      () async {
        when(client.fetchToken(auth)).thenSuccessWith(buildkiteToken);

        final result = await delegate.validateAuth(auth);

        expect(result.isSuccess, isTrue);
      },
    );

    test(
      ".validateAuth() returns a field validation result with the fetched Buildkite token data, if the fetched token is valid, but does not have the read artifacts scope",
      () async {
        when(client.fetchToken(auth)).thenSuccessWith(buildkiteToken);

        final result = await delegate.validateAuth(auth);
        final token = result.data;

        expect(token, equals(buildkiteToken));
      },
    );

    test(
      ".validateAuth() returns a field validation result with the 'token does not have read artifacts scope' additional context, if the fetched is valid, but token does not have the read artifacts token scope",
      () async {
        when(client.fetchToken(auth)).thenSuccessWith(buildkiteToken);

        final result = await delegate.validateAuth(auth);
        final additionalContext = result.additionalContext;

        expect(
          additionalContext,
          equals(BuildkiteStrings.tokenDoesNotHaveReadArtifactsScope),
        );
      },
    );

    test(
      ".validateAuth() returns a successful field validation result, if the fetched Buildkite token has the read builds and read artifacts scopes",
      () async {
        when(client.fetchToken(auth)).thenSuccessWith(
          const BuildkiteToken(scopes: readBuildsAndArtifactsScopes),
        );

        final result = await delegate.validateAuth(auth);

        expect(result.isSuccess, isTrue);
      },
    );

    test(
      ".validateAuth() returns a field validation result with the fetched Buildkite token data, if the fetched Buildkite token has the read builds and read artifacts scopes",
      () async {
        const buildkiteToken = BuildkiteToken(
          scopes: readBuildsAndArtifactsScopes,
        );
        when(client.fetchToken(auth)).thenSuccessWith(buildkiteToken);

        final result = await delegate.validateAuth(auth);
        final token = result.data;

        expect(token, equals(buildkiteToken));
      },
    );

    test(
      ".validatePipelineSlug() returns a failure field validation result, if the result of an interaction with the client is not successful",
      () async {
        when(client.fetchPipeline(pipelineSlug)).thenErrorWith();

        final result = await delegate.validatePipelineSlug(
          pipelineSlug,
        );

        expect(result.isFailure, isTrue);
      },
    );

    test(
      ".validatePipelineSlug() returns a field validation result with the 'pipeline not found' additional context, if the interaction with the client is not successful",
      () async {
        when(client.fetchPipeline(pipelineSlug)).thenErrorWith();

        final result = await delegate.validatePipelineSlug(
          pipelineSlug,
        );
        final additionalContext = result.additionalContext;

        expect(additionalContext, equals(BuildkiteStrings.pipelineNotFound));
      },
    );

    test(
      ".validatePipelineSlug() returns a failure field validation result, if the result of an interaction with the client is null",
      () async {
        when(
          client.fetchPipeline(pipelineSlug),
        ).thenSuccessWith(null);

        final result = await delegate.validatePipelineSlug(
          pipelineSlug,
        );

        expect(result.isFailure, isTrue);
      },
    );

    test(
      ".validatePipelineSlug() returns a field validation result with the 'pipeline not found' additional context, if the result of an interaction with the client is null",
      () async {
        when(
          client.fetchPipeline(pipelineSlug),
        ).thenSuccessWith(null);

        final result = await delegate.validatePipelineSlug(
          pipelineSlug,
        );
        final additionalContext = result.additionalContext;

        expect(additionalContext, equals(BuildkiteStrings.pipelineNotFound));
      },
    );

    test(
      ".validatePipelineSlug() returns a successful field validation result, if the given pipeline slug is valid",
      () async {
        when(
          client.fetchPipeline(pipelineSlug),
        ).thenSuccessWith(buildkitePipeline);

        final result = await delegate.validatePipelineSlug(
          pipelineSlug,
        );

        expect(result.isSuccess, isTrue);
      },
    );

    test(
      ".validateOrganizationSlug() returns a failure field validation result, if the interaction with the client is not successful",
      () async {
        when(
          client.fetchOrganization(organizationSlug),
        ).thenErrorWith();

        final result = await delegate.validateOrganizationSlug(
          organizationSlug,
        );

        expect(result.isFailure, isTrue);
      },
    );

    test(
      ".validateOrganizationSlug() returns a field validation result with the 'organization not found' additional context, if the interaction with the client is not successful",
      () async {
        when(
          client.fetchOrganization(organizationSlug),
        ).thenErrorWith();

        final result = await delegate.validateOrganizationSlug(
          organizationSlug,
        );
        final additionalContext = result.additionalContext;
        expect(
            additionalContext, equals(BuildkiteStrings.organizationNotFound));
      },
    );

    test(
      ".validateOrganizationSlug() returns a failure field validation result, if the result of an interaction with the client is null",
      () async {
        when(
          client.fetchOrganization(organizationSlug),
        ).thenSuccessWith(null);

        final result = await delegate.validateOrganizationSlug(
          organizationSlug,
        );

        expect(result.isFailure, isTrue);
      },
    );

    test(
      ".validateOrganizationSlug() returns a field validation result with the 'organization not found' additional context, if the result of an interaction with the client is null",
      () async {
        when(
          client.fetchOrganization(organizationSlug),
        ).thenSuccessWith(null);

        final result = await delegate.validateOrganizationSlug(
          organizationSlug,
        );
        final additionalContext = result.additionalContext;

        expect(
          additionalContext,
          equals(BuildkiteStrings.organizationNotFound),
        );
      },
    );

    test(
      ".validateOrganizationSlug() returns a successful field validation result, if the given organization slug is valid",
      () async {
        when(
          client.fetchOrganization(organizationSlug),
        ).thenSuccessWith(buildkiteOrganization);

        final result = await delegate.validateOrganizationSlug(
          organizationSlug,
        );

        expect(result.isSuccess, isTrue);
      },
    );
  });
}
