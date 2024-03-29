﻿// Copyright (c) Fynydd LLC.
// Licensed under the GNU GPLv3 License.

using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Data.SqlClient;

namespace SQribe.Halide.Core;

/// <summary>
/// Execute a T-SQL stored procedure or command text that has no return value.
/// Does not need to be disposed.
/// </summary>
/// <example>
/// <code>
/// try
/// {
///     SqlServer.Execute(new SqlExecuteSettings
///     {
///         ConnectionString = sqlConnectionString,
///         CommandText = commandText
///     });
/// }
///   
/// catch (Exception e)
/// {
///   	throw new Exception($"Uh oh => {e.Message}");
/// }
/// </code>
/// </example>
/// <example>
/// <code>
/// try
/// {
///     await SqlServer.ExecuteAsync(new SqlExecuteSettings
///     {
///         ConnectionString = sqlConnectionString,
///         CommandText = commandText
///     });
/// }
///   
/// catch (Exception e)
/// {
///   	throw new Exception($"Uh oh => {e.Message}");
/// }
/// </code>
/// </example>
public sealed class SqlServer
{
	public static void Execute(SqlExecuteSettings sqlExecuteSettings)
	{
		var builder = new SqlConnectionStringBuilder(sqlExecuteSettings.ConnectionString)
		{
			TrustServerCertificate = true
		};

		using (var sqlConnection = new SqlConnection(builder.ToString()))
		{
			using (var sqlCmd = new SqlCommand())
			{
				sqlCmd.CommandText = sqlExecuteSettings.CommandText;
				sqlCmd.Connection = sqlConnection;

				if (sqlExecuteSettings.ParametersDictionary.Any())
				{
					foreach (var (key, value) in sqlExecuteSettings.ParametersDictionary)
					{
						sqlCmd.Parameters.AddWithValue(key, value);
					}

					sqlCmd.CommandType = CommandType.StoredProcedure;
				}

				try
				{
					sqlConnection.Open();

					using (var sqlDataReader = sqlCmd.ExecuteReader())
					{
						sqlDataReader.Close();
					}
				}

				catch (Exception e)
				{
					if (sqlConnection.State != ConnectionState.Closed)
						sqlConnection.Close();

					throw new Exception($"SqlExecute() => {e.Message}");
				}
			}

			sqlConnection.Close();
		}
	}
	
	public static async Task ExecuteAsync(SqlExecuteSettings sqlExecuteSettings)
	{
		var builder = new SqlConnectionStringBuilder(sqlExecuteSettings.ConnectionString)
		{
			TrustServerCertificate = true
		};
		
		await using (var sqlConnection = new SqlConnection(builder.ToString()))
		{
			await using (var sqlCmd = new SqlCommand())
			{
				sqlCmd.CommandText = sqlExecuteSettings.CommandText;
				sqlCmd.Connection = sqlConnection;

				if (sqlExecuteSettings.ParametersDictionary.Any())
				{
					foreach (var (key, value) in sqlExecuteSettings.ParametersDictionary)
					{
						sqlCmd.Parameters.AddWithValue(key, value);
					}

					sqlCmd.CommandType = CommandType.StoredProcedure;
				}

				try
				{
					await sqlConnection.OpenAsync();

					await using (var sqlDataReader = await sqlCmd.ExecuteReaderAsync())
					{
						await sqlDataReader.CloseAsync();
					}
				}

				catch (Exception e)
				{
					if (sqlConnection.State != ConnectionState.Closed)
						await sqlConnection.CloseAsync();

					throw new Exception($"SqlExecute() => {e.Message}");
				}
			}

			await sqlConnection.CloseAsync();
		}
	}
}

/// <summary>
/// Settings for the SqlExecute class.
/// </summary>
public sealed class SqlExecuteSettings
{
	public string CommandText { get; init; } = string.Empty;
	public string ConnectionString { get; init; } = string.Empty;

	private readonly Dictionary<string, object> _parametersDictionary;
	public Dictionary<string, object> ParametersDictionary
	{
		get => _parametersDictionary;
		init => _parametersDictionary = value;
	}

	public int CommandTimeoutSeconds { get; init; }

	public SqlExecuteSettings()
	{
		_parametersDictionary = new Dictionary<string, object>();
	}
}
