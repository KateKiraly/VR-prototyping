using UnityEngine;
using UnityEngine.XR.Interaction.Toolkit;
using TMPro;

public class RubbleSpawner : MonoBehaviour
{
    public GameObject rubblePrefab;     // your prefab
    public TMP_Text inventoryText;      // the HUD text
    public int structuresLeft = 5;

    void Start()
    {
        UpdateText();
        var interactable = GetComponent<UnityEngine.XR.Interaction.Toolkit.Interactables.XRSimpleInteractable>();
        interactable.selectEntered.AddListener(OnGrabbed);
    }

    void OnGrabbed(SelectEnterEventArgs args)
    {
        if (structuresLeft <= 0) return;

        // spawn rubble at the hand
        GameObject newRubble = Instantiate(rubblePrefab,
            args.interactorObject.transform.position,
            args.interactorObject.transform.rotation);

        // make the hand grab it straight away
        var interactor = args.interactorObject as UnityEngine.XR.Interaction.Toolkit.Interactors.IXRSelectInteractor;
        var grabbable = newRubble.GetComponent<UnityEngine.XR.Interaction.Toolkit.Interactables.XRGrabInteractable>();
        grabbable.interactionManager.SelectEnter(interactor, grabbable);

        structuresLeft--;
        UpdateText();
    }

    void UpdateText()
    {
        inventoryText.text = "Structures left: " + structuresLeft;
    }
}