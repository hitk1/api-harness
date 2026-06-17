defmodule ApiHarness.AccountsTest do
  use ApiHarness.DataCase, async: true

  alias ApiHarness.Accounts
  alias ApiHarness.Accounts.User

  @valid_attrs %{name: "Eduardo", email: "eduardo@example.com", password: "s3cr3tpass"}

  describe "create_user/1" do
    test "creates user with valid attrs and hashes password" do
      assert {:ok, %User{} = user} = Accounts.create_user(@valid_attrs)
      assert user.name == "Eduardo"
      assert user.email == "eduardo@example.com"
      assert is_nil(user.password)
      assert user.hashed_password != "s3cr3tpass"
      assert user.token_version == 0
    end

    test "downcases email" do
      assert {:ok, user} = Accounts.create_user(%{@valid_attrs | email: "EDUARDO@EXAMPLE.COM"})
      assert user.email == "eduardo@example.com"
    end

    test "rejects duplicate email" do
      assert {:ok, _} = Accounts.create_user(@valid_attrs)
      assert {:error, changeset} = Accounts.create_user(@valid_attrs)
      assert "has already been taken" in errors_on(changeset).email
    end

    test "requires name, email, password" do
      assert {:error, changeset} = Accounts.create_user(%{})
      assert errors_on(changeset).name
      assert errors_on(changeset).email
      assert errors_on(changeset).password
    end

    test "rejects password shorter than 8 chars" do
      assert {:error, changeset} = Accounts.create_user(%{@valid_attrs | password: "short"})
      assert errors_on(changeset).password
    end
  end

  describe "list_users/0" do
    test "returns all users" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      users = Accounts.list_users()
      assert Enum.any?(users, &(&1.id == user.id))
    end
  end

  describe "get_user/1" do
    test "returns user by id" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      assert Accounts.get_user(user.id).id == user.id
    end

    test "accepts string id" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      assert Accounts.get_user(to_string(user.id)).id == user.id
    end

    test "returns nil for unknown id" do
      assert Accounts.get_user(0) == nil
    end
  end

  describe "update_user/2" do
    test "updates user name" do
      {:ok, user} = Accounts.create_user(@valid_attrs)

      assert {:ok, updated} =
               Accounts.update_user(user, %{name: "Novo Nome", password: "s3cr3tpass"})

      assert updated.name == "Novo Nome"
    end
  end

  describe "delete_user/1" do
    test "removes user" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      assert {:ok, _} = Accounts.delete_user(user)
      assert Accounts.get_user(user.id) == nil
    end
  end

  describe "verify_password/2" do
    test "returns {:ok, user} with correct password" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      assert {:ok, ^user} = Accounts.verify_password(user, "s3cr3tpass")
    end

    test "returns {:error, :invalid_credentials} with wrong password" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      assert {:error, :invalid_credentials} = Accounts.verify_password(user, "wrongpass")
    end
  end
end
