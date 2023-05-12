// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import {UnitTest} from "tests/bases/UnitTest.sol";
import {DeploymentUtils} from "tests/utils/core/DeploymentUtils.sol";
import {UpdateType} from "tests/utils/core/ListRegistryUtils.sol";

import {IDispatcher} from "tests/interfaces/internal/IDispatcher.sol";
import {IUintListRegistry} from "tests/interfaces/internal/IUintListRegistry.sol";

abstract contract UintListRegistryTest is UnitTest, DeploymentUtils {
    address internal dispatcher = makeAddr("DummyDispatcher");
    IUintListRegistry internal registry;

    function setUp() public {
        registry = deployUintListRegistry(IDispatcher(dispatcher));
    }

    function makeArray(uint256 _first) public pure returns (uint256[] memory list_) {
        list_ = new uint256[](1);
        list_[0] = _first;
    }

    function makeArray(uint256 _first, uint256 _second) public pure returns (uint256[] memory list_) {
        list_ = new uint256[](2);
        list_[0] = _first;
        list_[1] = _second;
    }

    function makeArray(uint256 _first, uint256 _second, uint256 _third) public pure returns (uint256[] memory list_) {
        list_ = new uint256[](3);
        list_[0] = _first;
        list_[1] = _second;
        list_[2] = _third;
    }
}

contract UintListRegistryConstructorTest is UintListRegistryTest {
    function testInitialState() public {
        assertEq(dispatcher, registry.getDispatcher());

        // The first list at position 0 is created as an empty list.
        assertEq(1, registry.getListCount());
        assertEq(uint256(UpdateType.None), uint256(registry.getListUpdateType(0)));
        assertEq(address(0), registry.getListOwner(0));
    }
}

contract UintListRegistrySetListOwnerTest is UintListRegistryTest {
    event ListOwnerSet(uint256 indexed id, address indexed nextOwner);

    function testDoesNotAllowArbitraryCaller() public {
        uint256 bobsList = registry.createList(bob, uint8(UpdateType.AddAndRemove), makeArray(123));

        vm.prank(alice);
        vm.expectRevert("Only callable by list owner");
        registry.setListOwner(bobsList, alice);
    }

    function testAllowsTransferOfOwnershipByTheCurrentOwner() public {
        uint256 bobsList = registry.createList(bob, uint8(UpdateType.AddAndRemove), makeArray(123));

        assertEq(bob, registry.getListOwner(bobsList));

        vm.expectEmit(true, true, true, true, address(registry));
        emit ListOwnerSet(bobsList, alice);

        vm.prank(bob);
        registry.setListOwner(bobsList, alice);

        assertEq(alice, registry.getListOwner(bobsList));
    }
}

contract UintListRegistrySetListUpdateTypeTest is UintListRegistryTest {
    event ListUpdateTypeSet(uint256 indexed id, UpdateType prevUpdateType, UpdateType indexed nextUpdateType);

    function assertAllowedUpdateTypeChange(UpdateType _prevUpdateType, UpdateType _nextUpdateType) public {
        uint256 bobsList = registry.createList(bob, uint8(_prevUpdateType), makeArray(123));

        assertEq(uint256(_prevUpdateType), uint256(registry.getListUpdateType(bobsList)));

        vm.expectEmit(true, true, true, true, address(registry));
        emit ListUpdateTypeSet(bobsList, _prevUpdateType, _nextUpdateType);

        vm.prank(bob);
        registry.setListUpdateType(bobsList, uint8(_nextUpdateType));

        assertEq(uint256(_nextUpdateType), uint256(registry.getListUpdateType(bobsList)));
    }

    function assertForbiddenUpdateTypeChange(UpdateType _prevUpdateType, UpdateType _nextUpdateType) public {
        uint256 bobsList = registry.createList(bob, uint8(_prevUpdateType), makeArray(123));

        assertEq(uint256(_prevUpdateType), uint256(registry.getListUpdateType(bobsList)));

        vm.prank(bob);
        vm.expectRevert("setListUpdateType: _nextUpdateType not allowed");
        registry.setListUpdateType(bobsList, uint8(_nextUpdateType));

        assertEq(uint256(_prevUpdateType), uint256(registry.getListUpdateType(bobsList)));
    }

    function testDoesNotAllowArbitraryCaller() public {
        uint256 bobsList = registry.createList(bob, uint8(UpdateType.AddAndRemove), makeArray(123));

        vm.prank(alice);
        vm.expectRevert("Only callable by list owner");
        registry.setListUpdateType(bobsList, uint8(UpdateType.None));
    }

    // TODO: This could be modeled better using tabled testing: https://github.com/foundry-rs/foundry/issues/858
    function testAllowedUpdateTypeChanges() public {
        assertAllowedUpdateTypeChange(UpdateType.AddAndRemove, UpdateType.AddOnly);
        assertAllowedUpdateTypeChange(UpdateType.AddAndRemove, UpdateType.RemoveOnly);
        assertAllowedUpdateTypeChange(UpdateType.AddAndRemove, UpdateType.None);
        assertAllowedUpdateTypeChange(UpdateType.AddOnly, UpdateType.None);
        assertAllowedUpdateTypeChange(UpdateType.RemoveOnly, UpdateType.None);
    }

    // TODO: This could be modeled better using tabled testing: https://github.com/foundry-rs/foundry/issues/858
    function testForbiddenUpdateTypeChanges() public {
        assertForbiddenUpdateTypeChange(UpdateType.RemoveOnly, UpdateType.AddAndRemove);
        assertForbiddenUpdateTypeChange(UpdateType.AddOnly, UpdateType.AddAndRemove);
        assertForbiddenUpdateTypeChange(UpdateType.None, UpdateType.AddOnly);
        assertForbiddenUpdateTypeChange(UpdateType.None, UpdateType.RemoveOnly);
        assertForbiddenUpdateTypeChange(UpdateType.None, UpdateType.AddAndRemove);
    }
}

contract UintListRegistryCreateListTest is UintListRegistryTest {
    event ItemAddedToList(uint256 indexed id, uint256 item);
    event ListCreated(address indexed creator, address indexed owner, uint256 id, UpdateType updateType);

    // TODO: This is an example for fuzzy testing in foundry. This particular example could possibly be modeled better
    // using fixed testing tables (https://github.com/foundry-rs/foundry/issues/858) but it's still a good and simple demo.
    function testFuzzyHappyPath(uint8 _enumIndex, uint8 _firstValue, uint8 _secondValue, uint8 _otherValue) public {
        // Assume that `otherValue` is neither `firstValue` nor `secondValue` and that both values are different.
        vm.assume(_firstValue != _otherValue);
        vm.assume(_secondValue != _otherValue);
        vm.assume(_firstValue != _secondValue);

        // Assume that `enumIndex` is the uint representation of one of the available UpdateTypes.
        vm.assume(_enumIndex <= 3);
        UpdateType updateType = UpdateType(_enumIndex);

        vm.expectEmit(true, true, true, true, address(registry));
        emit ListCreated(bob, bob, 1, updateType);

        vm.expectEmit(true, true, true, true, address(registry));
        emit ItemAddedToList(1, _firstValue);

        vm.expectEmit(true, true, true, true, address(registry));
        emit ItemAddedToList(1, _secondValue);

        vm.prank(bob);
        uint256 listId = registry.createList(bob, uint8(updateType), makeArray(_firstValue, _secondValue));

        assertEq(1, listId);
        assertEq(2, registry.getListCount());
        assertEq(bob, registry.getListOwner(listId));
        assertEq(uint256(updateType), uint256(registry.getListUpdateType(listId)));

        assertTrue(registry.isInList(listId, _firstValue));
        assertTrue(registry.isInList(listId, _secondValue));
        assertFalse(registry.isInList(listId, _otherValue));
    }
}

contract UintListRegistryAddToListTest is UintListRegistryTest {
    event ItemAddedToList(uint256 indexed id, uint256 item);

    function testDoesNotAllowArbitraryCaller() public {
        uint256 bobsList = registry.createList(bob, uint8(UpdateType.AddAndRemove), makeArray(123));

        vm.prank(alice);
        vm.expectRevert("Only callable by list owner");
        registry.addToList(bobsList, makeArray(123));
    }

    function testAllowsListOwnedByDispatcherToBeUpdatedByDispatcherOwner() public {
        uint256 dispatchersList = registry.createList(dispatcher, uint8(UpdateType.AddAndRemove), makeArray(123));

        // Pretend that bob is the dispatcher owner.
        vm.mockCall(dispatcher, abi.encodeWithSelector(IDispatcher.getOwner.selector), abi.encode(bob));

        // Calling the function as alice should fail.
        vm.prank(alice);
        vm.expectRevert("Only callable by list owner");
        registry.addToList(dispatchersList, makeArray(123));

        // Calling the function as bob should succeed.
        vm.prank(bob);
        registry.addToList(dispatchersList, makeArray(123));
    }

    function testDoesNotAllowUpdatingListIfUpdateTypeIsNone() public {
        uint256 bobsList = registry.createList(bob, uint8(UpdateType.None), makeArray(123));

        vm.prank(bob);
        vm.expectRevert("addToList: Cannot add to list");
        registry.addToList(bobsList, makeArray(123));
    }

    function testDoesNotAllowUpdatingListIfUpdateTypeIsRemoveOnly() public {
        uint256 bobsList = registry.createList(bob, uint8(UpdateType.RemoveOnly), makeArray(123));

        vm.prank(bob);
        vm.expectRevert("addToList: Cannot add to list");
        registry.addToList(bobsList, makeArray(123));
    }

    function testCorrectlyHandlesUpdateTypeAddOnly() public {
        uint256 bobsList = registry.createList(bob, uint8(UpdateType.AddOnly), makeArray(123));

        assertTrue(registry.isInList(bobsList, 123));
        assertFalse(registry.isInList(bobsList, 456));
        assertFalse(registry.isInList(bobsList, 1337));

        vm.expectEmit(true, true, true, true, address(registry));
        emit ItemAddedToList(bobsList, 456);

        vm.expectEmit(true, true, true, true, address(registry));
        emit ItemAddedToList(bobsList, 1337);

        vm.prank(bob);
        registry.addToList(bobsList, makeArray(456, 1337));

        assertTrue(registry.isInList(bobsList, 123));
        assertTrue(registry.isInList(bobsList, 456));
        assertTrue(registry.isInList(bobsList, 1337));
    }

    function testCorrectlyHandlesUpdateTypeAddAndRemove() public {
        uint256 bobsList = registry.createList(bob, uint8(UpdateType.AddAndRemove), makeArray(123));

        assertTrue(registry.isInList(bobsList, 123));
        assertFalse(registry.isInList(bobsList, 456));
        assertFalse(registry.isInList(bobsList, 1337));

        vm.expectEmit(true, true, true, true, address(registry));
        emit ItemAddedToList(bobsList, 456);

        vm.expectEmit(true, true, true, true, address(registry));
        emit ItemAddedToList(bobsList, 1337);

        vm.prank(bob);
        registry.addToList(bobsList, makeArray(456, 1337));

        assertTrue(registry.isInList(bobsList, 123));
        assertTrue(registry.isInList(bobsList, 456));
        assertTrue(registry.isInList(bobsList, 1337));
    }
}

contract UintListRegistryRemoveFromListTest is UintListRegistryTest {
    event ItemRemovedFromList(uint256 indexed id, uint256 item);

    function testDoesNotAllowArbitraryCaller() public {
        uint256 bobsList = registry.createList(bob, uint8(UpdateType.AddAndRemove), makeArray(123, 456));

        vm.prank(alice);
        vm.expectRevert("Only callable by list owner");
        registry.removeFromList(bobsList, makeArray(123, 456));
    }

    function testDoesNotAllowRemovingFromListIfUpdateTypeIsNone() public {
        uint256 bobsList = registry.createList(bob, uint8(UpdateType.None), makeArray(123));

        vm.prank(bob);
        vm.expectRevert("removeFromList: Cannot remove from list");
        registry.removeFromList(bobsList, makeArray(123));
    }

    function testDoesNotAllowRemovingFromListIfUpdateTypeIsAddOnly() public {
        uint256 bobsList = registry.createList(bob, uint8(UpdateType.AddOnly), makeArray(123));

        vm.prank(bob);
        vm.expectRevert("removeFromList: Cannot remove from list");
        registry.removeFromList(bobsList, makeArray(123));
    }

    // TODO: This is a test that is expected to fail and passes if it does. This would be better implemented using negative
    // assertions as described here: https://github.com/foundry-rs/foundry/issues/509
    function testFailSilentlyIgnoresRemovalOfNonExistentItems() public {
        uint256 bobsList = registry.createList(bob, uint8(UpdateType.AddAndRemove), makeArray(123));

        assertTrue(registry.isInList(bobsList, 123));
        assertFalse(registry.isInList(bobsList, 456));

        // This expectEmit will fail because 456 is not in the list and we expect it to NOT emit an event for its
        // removal. But because our test uses the `fail` modifier, it will pass.
        vm.expectEmit(true, true, true, true, address(registry));
        emit ItemRemovedFromList(bobsList, 456);

        vm.prank(bob);
        registry.removeFromList(bobsList, makeArray(456));
    }

    function testCorrectlyHandlesUpdateTypeRemoveOnly() public {
        uint256 bobsList = registry.createList(bob, uint8(UpdateType.RemoveOnly), makeArray(123, 456, 1337));

        assertTrue(registry.isInList(bobsList, 123));
        assertTrue(registry.isInList(bobsList, 456));
        assertTrue(registry.isInList(bobsList, 1337));

        vm.expectEmit(true, true, true, true, address(registry));
        emit ItemRemovedFromList(bobsList, 456);

        vm.prank(bob);
        registry.removeFromList(bobsList, makeArray(456, 1337));

        assertTrue(registry.isInList(bobsList, 123));
        assertFalse(registry.isInList(bobsList, 456));
        assertFalse(registry.isInList(bobsList, 1337));
    }

    function testCorrectlyHandlesUpdateTypeAddAndRemove() public {
        uint256 bobsList = registry.createList(bob, uint8(UpdateType.AddAndRemove), makeArray(123, 456, 1337));

        assertTrue(registry.isInList(bobsList, 123));
        assertTrue(registry.isInList(bobsList, 456));
        assertTrue(registry.isInList(bobsList, 1337));

        vm.expectEmit(true, true, true, true, address(registry));
        emit ItemRemovedFromList(bobsList, 456);

        vm.prank(bob);
        registry.removeFromList(bobsList, makeArray(456, 1337));

        assertTrue(registry.isInList(bobsList, 123));
        assertFalse(registry.isInList(bobsList, 456));
        assertFalse(registry.isInList(bobsList, 1337));
    }
}

contract UintListRegistryListSearchTest is UintListRegistryTest {
    function assumeFuzzParameters(
        uint256 _inNoLists,
        uint256 _inFirstListOnly,
        uint256 _inSecondListOnly,
        uint256 _inAllListsA,
        uint256 _inAllListsB
    ) public pure {
        // Assume that `_inNoLists` doesn't equal any other fuzz value.
        vm.assume(_inNoLists != _inFirstListOnly);
        vm.assume(_inNoLists != _inSecondListOnly);
        vm.assume(_inNoLists != _inAllListsA);
        vm.assume(_inNoLists != _inAllListsB);

        // Assume that there are no duplicates in any of the other values either.
        vm.assume(_inFirstListOnly != _inAllListsA);
        vm.assume(_inFirstListOnly != _inAllListsB);

        vm.assume(_inSecondListOnly != _inAllListsA);
        vm.assume(_inSecondListOnly != _inAllListsB);

        vm.assume(_inSecondListOnly != _inFirstListOnly);
    }

    function createLists(
        uint256 _inNoLists,
        uint256 _inFirstListOnly,
        uint256 _inSecondListOnly,
        uint256 _inAllListsA,
        uint256 _inAllListsB
    ) public returns (uint256 firstList_, uint256 secondList_, uint256 emptyList_) {
        assumeFuzzParameters(_inNoLists, _inFirstListOnly, _inSecondListOnly, _inAllListsA, _inAllListsB);

        uint256[] memory firstListItems = makeArray(_inFirstListOnly, _inAllListsA, _inAllListsB);
        uint256[] memory secondListItems = makeArray(_inSecondListOnly, _inAllListsA, _inAllListsB);

        firstList_ = registry.createList(bob, uint8(UpdateType.None), firstListItems);
        secondList_ = registry.createList(bob, uint8(UpdateType.None), secondListItems);
        emptyList_ = registry.createList(bob, uint8(UpdateType.None), new uint256[](0));
    }

    function testIsInAllLists(
        uint256 _inNoLists,
        uint256 _inFirstListOnly,
        uint256 _inSecondListOnly,
        uint256 _inAllListsA,
        uint256 _inAllListsB
    ) public {
        (uint256 firstList, uint256 secondList, uint256 emptyList) =
            createLists(_inNoLists, _inFirstListOnly, _inSecondListOnly, _inAllListsA, _inAllListsB);

        assertFalse(registry.isInAllLists(makeArray(firstList, secondList), _inNoLists));
        assertFalse(registry.isInAllLists(makeArray(firstList, secondList), _inFirstListOnly));
        assertFalse(registry.isInAllLists(makeArray(firstList, secondList, emptyList), _inAllListsA));
        assertTrue(registry.isInAllLists(makeArray(firstList, secondList), _inAllListsB));
    }

    function testIsInSomeOfLists(
        uint256 _inNoLists,
        uint256 _inFirstListOnly,
        uint256 _inSecondListOnly,
        uint256 _inAllListsA,
        uint256 _inAllListsB
    ) public {
        (uint256 firstList, uint256 secondList, uint256 emptyList) =
            createLists(_inNoLists, _inFirstListOnly, _inSecondListOnly, _inAllListsA, _inAllListsB);

        assertFalse(registry.isInSomeOfLists(makeArray(firstList, secondList, emptyList), _inNoLists));
        assertTrue(registry.isInSomeOfLists(makeArray(firstList, secondList, emptyList), _inFirstListOnly));
        assertTrue(registry.isInSomeOfLists(makeArray(firstList, secondList, emptyList), _inAllListsA));
    }

    function testAreAllInList(
        uint256 _inNoLists,
        uint256 _inFirstListOnly,
        uint256 _inSecondListOnly,
        uint256 _inAllListsA,
        uint256 _inAllListsB
    ) public {
        (uint256 firstList, uint256 secondList, uint256 emptyList) =
            createLists(_inNoLists, _inFirstListOnly, _inSecondListOnly, _inAllListsA, _inAllListsB);

        assertFalse(registry.areAllInList(firstList, makeArray(_inFirstListOnly, _inAllListsA, _inNoLists)));
        assertFalse(registry.areAllInList(emptyList, makeArray(_inAllListsA)));
        assertTrue(registry.areAllInList(firstList, makeArray(_inFirstListOnly, _inAllListsA)));
        assertTrue(registry.areAllInList(secondList, makeArray(_inSecondListOnly, _inAllListsA, _inAllListsB)));
    }

    function testAreAllNotInList(
        uint256 _inNoLists,
        uint256 _inFirstListOnly,
        uint256 _inSecondListOnly,
        uint256 _inAllListsA,
        uint256 _inAllListsB
    ) public {
        (uint256 firstList, uint256 secondList, uint256 emptyList) =
            createLists(_inNoLists, _inFirstListOnly, _inSecondListOnly, _inAllListsA, _inAllListsB);

        assertFalse(registry.areAllNotInList(firstList, makeArray(_inNoLists, _inAllListsA)));
        assertTrue(registry.areAllNotInList(secondList, makeArray(_inNoLists, _inFirstListOnly)));
        assertTrue(registry.areAllNotInList(emptyList, makeArray(_inAllListsA)));
    }

    function testAreAllInAllLists(
        uint256 _inNoLists,
        uint256 _inFirstListOnly,
        uint256 _inSecondListOnly,
        uint256 _inAllListsA,
        uint256 _inAllListsB
    ) public {
        (uint256 firstList, uint256 secondList, uint256 emptyList) =
            createLists(_inNoLists, _inFirstListOnly, _inSecondListOnly, _inAllListsA, _inAllListsB);

        assertFalse(
            registry.areAllInAllLists(makeArray(firstList, secondList), makeArray(_inAllListsA, _inFirstListOnly))
        );
        assertFalse(registry.areAllInAllLists(makeArray(firstList, emptyList), makeArray(_inAllListsB)));
        assertTrue(registry.areAllInAllLists(makeArray(firstList, secondList), makeArray(_inAllListsA, _inAllListsB)));
    }

    function testAreAllInSomeOfLists(
        uint256 _inNoLists,
        uint256 _inFirstListOnly,
        uint256 _inSecondListOnly,
        uint256 _inAllListsA,
        uint256 _inAllListsB
    ) public {
        (uint256 firstList, uint256 secondList, uint256 emptyList) =
            createLists(_inNoLists, _inFirstListOnly, _inSecondListOnly, _inAllListsA, _inAllListsB);

        assertFalse(
            registry.areAllInSomeOfLists(
                makeArray(firstList, secondList, emptyList), makeArray(_inFirstListOnly, _inSecondListOnly, _inNoLists)
            )
        );
        assertTrue(
            registry.areAllInSomeOfLists(
                makeArray(firstList, secondList, emptyList), makeArray(_inFirstListOnly, _inSecondListOnly)
            )
        );
    }

    function testAreAllNotInAnyOfLists(
        uint256 _inNoLists,
        uint256 _inFirstListOnly,
        uint256 _inSecondListOnly,
        uint256 _inAllListsA,
        uint256 _inAllListsB
    ) public {
        (uint256 firstList, uint256 secondList, uint256 emptyList) =
            createLists(_inNoLists, _inFirstListOnly, _inSecondListOnly, _inAllListsA, _inAllListsB);

        assertFalse(
            registry.areAllNotInAnyOfLists(makeArray(firstList, secondList), makeArray(_inSecondListOnly, _inNoLists))
        );
        assertTrue(
            registry.areAllNotInAnyOfLists(makeArray(firstList, emptyList), makeArray(_inSecondListOnly, _inNoLists))
        );
    }
}
