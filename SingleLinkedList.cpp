#include <iostream>
#include <ctime>

using namespace std;

template<typename T>
class List{
private:

    template<typename T>
    class Node{
    public:
        Node* next;
        T data;

        Node(T data = T(), Node* next = nullptr){
            this->data = data;
            this->next = next;
        }
    };

    Node<T>* head;
    int size;

public:

    List();
    ~List();
    void insert(T data, int position);
    void push_front(T data);
    void push_back(T data);
    void pop_front();
    void pop_back();
    void removeAt(int position);
    void clear();
    int getSize();
    T& operator[](const int index);
};

template<typename T>
List<T>::List() {
    head = nullptr;
    size = 0;
}

template<typename T>
List<T>::~List<T>() {
    clear();
}

template<typename T>
int List<T>::getSize() {
    return size;
}

template<typename T>
void List<T>::insert(T data, int position) {

    if(position == 0){
        push_front(data);
    }
    else{
        Node<T>* temp = head;

        for(int i = 0; i < position - 1; i++){
            temp = temp->next;
        }

        temp->next = new Node<T>(data, temp->next);
        size++;
    }
}

template<typename T>
void List<T>::push_back(T data) {

    if(head == nullptr){
        head = new Node<T>(data);
    }
    else {
        Node<T>* temp = this->head;

        while (temp->next != nullptr) {
            temp = temp->next;
        }

        temp->next = new Node<T>(data);
    }

    size++;
}


template<typename T>
void List<T>::push_front(T data) {
    head = new Node<T>(data, head);
    size++;
}

template<typename T>
void List<T>::pop_front() {
    Node<T>* temp = head;
    head = temp->next;
    delete temp;
    size--;

}

template<typename T>
void List<T>::pop_back() {
    Node<T>* temp = head;

    for(int i = 0; i < getSize() - 2; i++){
        temp = temp->next;
    }

    Node<T>* nodeToDelete = temp->next;
    temp->next = nullptr;

    delete nodeToDelete;
    size--;
}

template<typename T>
void List<T>::removeAt(int position) {

    if(position == 0){
        pop_front();
    }
    else {
        Node<T> *temp = head;

        for (int i = 0; i < position - 1; i++) {
            temp = temp->next;
        }

        Node<T> *nodeToDelete = temp->next;
        temp->next = nodeToDelete->next;

        delete nodeToDelete;
        size--;
    }
}

template<typename T>
void List<T>::clear(){
    while(size){
        pop_front();
    }
}

template<typename T>
T& List<T>::operator[](const int index){
    Node<T>* temp = head;
    int counter = 0;

    while(temp != nullptr){
        if(counter == index){
            return temp->data;
        }

        temp = temp->next;
        counter++;
    }
}

int main(){
    
    List<int> list;

    list.push_back(1);
    list.push_back(2);
    list.push_back(3);
    list.push_back(4);
    list.push_back(5);
    list.push_back(6);
    list.push_back(7);
    list.push_back(8);
    list.push_back(9);
    list.push_back(10);

//    list.pop_back();
//    list.push_back(11);
//    list.removeAt(4);
//    list.pop_front();
//    list.pop_back();
//    list.push_front(74);
//    list.push_back(36);
//    list.insert(0, 6);

    for(int i = 0; i < list.getSize(); i++){
        cout << "Element #" << i << " -> " << list[i] << endl;
    }

    cout << "Size: " << list.getSize() << endl;
}